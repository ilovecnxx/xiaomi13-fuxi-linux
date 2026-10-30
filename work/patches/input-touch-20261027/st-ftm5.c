// SPDX-License-Identifier: GPL-2.0-only
/*
 * STMicroelectronics FingerTip FTM5 touchscreen (SPI), e.g. Xiaomi 13 (fuxi).
 *
 * Protocol taken from the vendor GPL "fts_spi" driver: every access is
 * [opcode][address] followed by a read with one leading dummy byte; touch
 * events are 8-byte records read from the controller FIFO.
 */

#include <linux/delay.h>
#include <linux/gpio/consumer.h>
#include <linux/input.h>
#include <linux/input/mt.h>
#include <linux/input/touchscreen.h>
#include <linux/interrupt.h>
#include <linux/module.h>
#include <linux/regulator/consumer.h>
#include <linux/spi/spi.h>
#include <linux/unaligned.h>

#define FTM5_CMD_SCAN_MODE	0xa0
#define FTM5_CMD_FIFO_READ	0x87
#define FTM5_CMD_FRAMEBUF_R	0xa7

#define FTM5_SCAN_ACTIVE	0x00
#define FTM5_SCAN_MULTI_TOUCH	0x01

#define FTM5_EVENT_SIZE		8
#define FTM5_FIFO_DEPTH		32

#define FTM5_EVT_NONE		0x00
#define FTM5_EVT_READY		0x03
#define FTM5_EVT_ENTER		0x13
#define FTM5_EVT_MOTION		0x23
#define FTM5_EVT_LEAVE		0x33
#define FTM5_EVT_ERROR		0xf3

#define FTM5_SYSINFO_LEN	208
#define FTM5_SYSINFO_SIG	0xa5

#define FTM5_MAX_FINGERS	10
#define FTM5_CS_DELAY_US	10

struct ftm5 {
	struct spi_device *spi;
	struct input_dev *input;
	struct gpio_desc *reset;
	struct regulator_bulk_data supplies[2];
	struct touchscreen_properties prop;
	/* DMA-safe buffers: one dummy byte + the whole FIFO */
	u8 tx[8];
	u8 rx[1 + FTM5_EVENT_SIZE * FTM5_FIFO_DEPTH];
	u8 txbuf[8 + 1 + FTM5_EVENT_SIZE * FTM5_FIFO_DEPTH] ____cacheline_aligned;
	u8 rxbuf[8 + 1 + FTM5_EVENT_SIZE * FTM5_FIFO_DEPTH] ____cacheline_aligned;
};

static int ftm5_write(struct ftm5 *ts, const u8 *cmd, size_t len)
{
	struct spi_transfer xfer = {
		.tx_buf = ts->tx,
		.len = len,
		.delay = { .value = FTM5_CS_DELAY_US, .unit = SPI_DELAY_UNIT_USECS },
	};

	memcpy(ts->tx, cmd, len);
	return spi_sync_transfer(ts->spi, &xfer, 1);
}

/*
 * Send @cmd_len bytes from ts->tx and read @len bytes; the reply follows one dummy
 * byte, so the data ends up at ts->rx + 1. Done as one full-duplex transfer (MOSI
 * idles at 0 after the command), which every SPI controller mode handles.
 */
static int ftm5_read(struct ftm5 *ts, size_t cmd_len, size_t len)
{
	struct spi_transfer xfer = {
		.tx_buf = ts->txbuf,
		.rx_buf = ts->rxbuf,
		.len = cmd_len + 1 + len,
		.delay = { .value = FTM5_CS_DELAY_US, .unit = SPI_DELAY_UNIT_USECS },
	};
	int ret;

	memset(ts->txbuf, 0, xfer.len);
	memcpy(ts->txbuf, ts->tx, cmd_len);
	ret = spi_sync_transfer(ts->spi, &xfer, 1);
	if (ret)
		return ret;
	memcpy(ts->rx, ts->rxbuf + cmd_len, 1 + len);
	return 0;
}

static int ftm5_read_events(struct ftm5 *ts, unsigned int count)
{
	ts->tx[0] = FTM5_CMD_FIFO_READ;
	return ftm5_read(ts, 1, count * FTM5_EVENT_SIZE);
}

static int ftm5_sense_on(struct ftm5 *ts)
{
	static const u8 cmd[] = { FTM5_CMD_SCAN_MODE, FTM5_SCAN_ACTIVE, FTM5_SCAN_MULTI_TOUCH };

	return ftm5_write(ts, cmd, sizeof(cmd));
}

static int ftm5_sense_off(struct ftm5 *ts)
{
	static const u8 cmd[] = { FTM5_CMD_SCAN_MODE, FTM5_SCAN_ACTIVE, 0x00 };

	return ftm5_write(ts, cmd, sizeof(cmd));
}

/* Pulse reset and wait (~100 ms) for the "controller ready" event in the FIFO */
static int ftm5_reset(struct ftm5 *ts)
{
	int attempt, i, ret;

	for (attempt = 0; attempt < 3; attempt++) {
		gpiod_set_value_cansleep(ts->reset, 1);
		usleep_range(10000, 11000);
		gpiod_set_value_cansleep(ts->reset, 0);
		msleep(20);

		for (i = 0; i < 50; i++) {
			ret = ftm5_read_events(ts, 1);
			if (ret)
				return ret;
			if (ts->rx[1] == FTM5_EVT_READY)
				return 0;
			if (ts->rx[1] == FTM5_EVT_ERROR)
				dev_warn(&ts->spi->dev, "error event %*ph during reset\n",
					 FTM5_EVENT_SIZE, &ts->rx[1]);
			usleep_range(2000, 2500);
		}
	}
	return -ETIMEDOUT;
}

static void ftm5_log_sysinfo(struct ftm5 *ts)
{
	const u8 *d = &ts->rx[1];

	ts->tx[0] = FTM5_CMD_FRAMEBUF_R;
	ts->tx[1] = 0x00;
	ts->tx[2] = 0x00;
	if (ftm5_read(ts, 3, FTM5_SYSINFO_LEN) || d[0] != FTM5_SYSINFO_SIG) {
		dev_warn(&ts->spi->dev, "cannot read system info (header %02x)\n", d[0]);
		return;
	}
	dev_info(&ts->spi->dev, "chip %04x fw %04x cfg %04x panel %ux%u\n",
		 get_unaligned_le16(d + 10), get_unaligned_le16(d + 16),
		 get_unaligned_le16(d + 20), get_unaligned_le16(d + 80),
		 get_unaligned_le16(d + 82));
}

static int ftm5_start(struct ftm5 *ts)
{
	int ret;

	ret = ftm5_reset(ts);
	if (ret)
		return ret;
	return ftm5_sense_on(ts);
}

static void ftm5_handle_event(struct ftm5 *ts, const u8 *ev)
{
	struct input_dev *input = ts->input;
	unsigned int id = ev[1] >> 4;
	unsigned int x, y;

	switch (ev[0]) {
	case FTM5_EVT_ENTER:
	case FTM5_EVT_MOTION:
		if (id >= FTM5_MAX_FINGERS)
			break;
		/* super-resolution coordinates, 1/10 pixel */
		x = get_unaligned_le16(ev + 2);
		y = get_unaligned_le16(ev + 4);
		input_mt_slot(input, id);
		input_mt_report_slot_state(input, MT_TOOL_FINGER, true);
		touchscreen_report_pos(input, &ts->prop, x, y, true);
		input_report_abs(input, ABS_MT_TOUCH_MAJOR, ev[6] >> 4);
		input_report_abs(input, ABS_MT_TOUCH_MINOR, ev[6] & 0x0f);
		break;
	case FTM5_EVT_LEAVE:
		if (id >= FTM5_MAX_FINGERS)
			break;
		input_mt_slot(input, id);
		input_mt_report_slot_inactive(input);
		break;
	case FTM5_EVT_READY:
		/* controller restarted on its own (ESD, watchdog): scanning is off again */
		dev_warn(&ts->spi->dev, "controller reset, re-enabling scan\n");
		ftm5_sense_on(ts);
		break;
	case FTM5_EVT_ERROR:
		dev_warn(&ts->spi->dev, "error event %*ph\n", FTM5_EVENT_SIZE, ev);
		break;
	default:
		break;
	}
}

static irqreturn_t ftm5_irq(int irq, void *dev_id)
{
	struct ftm5 *ts = dev_id;
	unsigned int remaining, i;
	u8 events[FTM5_EVENT_SIZE * FTM5_FIFO_DEPTH];
	unsigned int count;

	if (ftm5_read_events(ts, 1))
		return IRQ_NONE;
	memcpy(events, &ts->rx[1], FTM5_EVENT_SIZE);
	count = 1;

	remaining = min(events[7] & 0x1f, FTM5_FIFO_DEPTH - 1);
	if (remaining && !ftm5_read_events(ts, remaining)) {
		memcpy(events + FTM5_EVENT_SIZE, &ts->rx[1], remaining * FTM5_EVENT_SIZE);
		count += remaining;
	}

	for (i = 0; i < count; i++) {
		const u8 *ev = events + i * FTM5_EVENT_SIZE;

		if (ev[0] == FTM5_EVT_NONE)
			break;
		ftm5_handle_event(ts, ev);
	}

	input_mt_sync_frame(ts->input);
	input_sync(ts->input);
	return IRQ_HANDLED;
}

static void ftm5_power_off(void *data)
{
	struct ftm5 *ts = data;

	gpiod_set_value_cansleep(ts->reset, 1);
	regulator_bulk_disable(ARRAY_SIZE(ts->supplies), ts->supplies);
}

static int ftm5_probe(struct spi_device *spi)
{
	struct device *dev = &spi->dev;
	struct input_dev *input;
	struct ftm5 *ts;
	int ret;

	ts = devm_kzalloc(dev, sizeof(*ts), GFP_KERNEL);
	if (!ts)
		return -ENOMEM;
	ts->spi = spi;
	spi_set_drvdata(spi, ts);

	spi->mode = SPI_MODE_0;
	spi->bits_per_word = 8;
	ret = spi_setup(spi);
	if (ret)
		return ret;

	ts->supplies[0].supply = "vdd";
	ts->supplies[1].supply = "avdd";
	ret = devm_regulator_bulk_get(dev, ARRAY_SIZE(ts->supplies), ts->supplies);
	if (ret)
		return dev_err_probe(dev, ret, "failed to get regulators\n");

	ts->reset = devm_gpiod_get(dev, "reset", GPIOD_OUT_HIGH);
	if (IS_ERR(ts->reset))
		return dev_err_probe(dev, PTR_ERR(ts->reset), "failed to get reset gpio\n");

	ret = regulator_bulk_enable(ARRAY_SIZE(ts->supplies), ts->supplies);
	if (ret)
		return dev_err_probe(dev, ret, "failed to enable regulators\n");
	ret = devm_add_action_or_reset(dev, ftm5_power_off, ts);
	if (ret)
		return ret;
	usleep_range(3000, 3500);

	ret = ftm5_reset(ts);
	if (ret)
		return dev_err_probe(dev, ret, "controller did not become ready\n");
	ftm5_log_sysinfo(ts);

	input = devm_input_allocate_device(dev);
	if (!input)
		return -ENOMEM;
	ts->input = input;
	input->name = "ST FTM5 Touchscreen";
	input->id.bustype = BUS_SPI;

	input_set_abs_params(input, ABS_MT_POSITION_X, 0, 10800 - 1, 0, 0);
	input_set_abs_params(input, ABS_MT_POSITION_Y, 0, 24000 - 1, 0, 0);
	input_set_abs_params(input, ABS_MT_TOUCH_MAJOR, 0, 15, 0, 0);
	input_set_abs_params(input, ABS_MT_TOUCH_MINOR, 0, 15, 0, 0);
	touchscreen_parse_properties(input, true, &ts->prop);

	ret = input_mt_init_slots(input, FTM5_MAX_FINGERS,
				  INPUT_MT_DIRECT | INPUT_MT_DROP_UNUSED);
	if (ret)
		return ret;

	ret = devm_request_threaded_irq(dev, spi->irq, NULL, ftm5_irq,
					IRQF_ONESHOT, "ftm5", ts);
	if (ret)
		return dev_err_probe(dev, ret, "failed to request irq\n");

	ret = input_register_device(input);
	if (ret)
		return ret;

	ret = ftm5_sense_on(ts);
	if (ret)
		return dev_err_probe(dev, ret, "failed to start scanning\n");
	return 0;
}

static int ftm5_suspend(struct device *dev)
{
	struct ftm5 *ts = dev_get_drvdata(dev);

	disable_irq(ts->spi->irq);
	ftm5_sense_off(ts);
	return 0;
}

static int ftm5_resume(struct device *dev)
{
	struct ftm5 *ts = dev_get_drvdata(dev);
	int ret;

	ret = ftm5_start(ts);
	enable_irq(ts->spi->irq);
	return ret;
}

static DEFINE_SIMPLE_DEV_PM_OPS(ftm5_pm_ops, ftm5_suspend, ftm5_resume);

static const struct of_device_id ftm5_of_match[] = {
	{ .compatible = "st,ftm5" },
	{ }
};
MODULE_DEVICE_TABLE(of, ftm5_of_match);

static const struct spi_device_id ftm5_spi_id[] = {
	{ "ftm5" },
	{ }
};
MODULE_DEVICE_TABLE(spi, ftm5_spi_id);

static struct spi_driver ftm5_driver = {
	.driver = {
		.name = "st-ftm5",
		.of_match_table = ftm5_of_match,
		.pm = pm_sleep_ptr(&ftm5_pm_ops),
	},
	.probe = ftm5_probe,
	.id_table = ftm5_spi_id,
};
module_spi_driver(ftm5_driver);

MODULE_DESCRIPTION("STMicroelectronics FTM5 SPI touchscreen driver");
MODULE_LICENSE("GPL");
