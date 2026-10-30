# removed-artifacts —— 从内核树移除的误提交文件

## drivers/net/ipa/ipa_mem.c.orig

- **原路径**：`build/linux/drivers/net/ipa/ipa_mem.c.orig`
- **性质**：打 modem13 补丁时留下的备份文件（`patch` 的 `--backup` 产物），在 `fuxi/20261031` 分支首次提交时被误纳入。
- **为什么移除**：不是源码、不参与编译，进入全量补丁只会污染变更清单与复现记录。
- **备份哈希**：sha256 `f4962e5109c4f5654eec42127e2078da7ab89d3144a9241439876ea9536e6e34`（19,119 B）
- **移除提交**：`18e74dc1d`（fuxi 分支，位于 `c3890463b` 之后）
- 内容为 modem13 之前的 `ipa_mem.c`：没有 `ipa_smem_map_region()` 与 `#include <linux/of.h>`；diff 与正式文件相差 73 行。
