# 🧠 排障思维训练：H20 + DeepSeek-V4 部署实录

> 这不是一篇普通的安装教程，而是一份**排障思维导图**。
> 重点不在于"做了什么"，而在于**为什么怀疑它、怎么验证、如何举一反三**。

---

## 排障四步法

```
症状出现
   │
   ▼
① 收集触发信号 ──→ 这个报错具体说了什么？
   │
   ▼
② 构建假设列表 ──→ 按可能性从高到低排列
   │
   ▼
③ 用最小成本验证假设 ──→ 选一个验证成本最低的入手
   │
   ▼
④ 确认根因 / 排除假设 ──→ 缩小范围，进入下一轮
```

---

## 实战推演

### 假设优先级原则

驱动 > 中间件 > 配置 > 镜像

- **驱动问题** → 验证成本 1 条命令（nvidia-smi + CUDA 版本对比）
- **中间件问题** → 验证成本 2 条命令（检查 service 状态）
- **配置问题** → 验证成本 3+ 条命令（对比不同环境参数）
- **镜像问题** → 验证成本最高（需要重新下载/构建）

### Step 1: Error 802

| 维度 | 内容 |
|------|------|
| **触发信号** | `Error 802`, `cudaGetDeviceCount() failed` |
| **假设列表** | ① 驱动版本 < 容器 CUDA 要求 ② 硬件故障 ③ 镜像损坏 |
| **验证** | nvidia-smi 对比 CUDA 版本，5 秒确认是驱动问题 |
| **根因** | 宿主机驱动 550 < 容器 CUDA 13.x 所需最低 570 |

### Step 2: No Accelerator

| 维度 | 内容 |
|------|------|
| **触发信号** | `No accelerator available`（升级驱动后仍出现） |
| **假设列表** | ① Container Toolkit 未装 ② Docker runtime 未配置 ③ 驱动残留 |
| **验证** | `systemctl status nvidia-container-toolkit` → Unit not found |
| **根因** | Container Toolkit 未安装，Docker 无法穿透 GPU |

### Step 3: 持续 Error 802

| 维度 | 内容 |
|------|------|
| **触发信号** | Error 802 在 Container Toolkit 装完**仍存在** |
| **假设列表** | ① Fabric Manager 版本不匹配 ② NVLink 初始化失败 ③ 其他内核模块 |
| **验证** | `systemctl status nvidia-fabricmanager` → version mismatch |
| **根因** | Fabric Manager 还停留在 550，驱动已升到 575 |

### Step 4: sub-optimal

| 维度 | 内容 |
|------|------|
| **触发信号** | `Using default MoE kernel config. Performance might be sub-optimal!` |
| **决策逻辑** | 服务已正常 → 这不是错误 → 不算阻塞项 → 以后优化 |
| **根因** | H20 没有对应预编译配置，降级使用通用内核 |

---

## 可迁移的排障直觉

### 直觉 1：怀疑链条

```
nvidia-smi 正常
    → docker run --gpus all nvidia-smi 正常
        → torch.cuda.is_available() 失败
            → 问题在 Docker 和 PyTorch 之间的层
```

每一层有各自的验证工具：
| 层 | 验证命令 |
|----|---------|
| 硬件 | `nvidia-smi` |
| Docker 穿透 | `docker run --rm --gpus all nvidia-smi` |
| PyTorch 绑定 | `python -c "import torch; print(torch.cuda.is_available())"` |
| NVLink 通信 | `systemctl status nvidia-fabricmanager` |

### 直觉 2：升级驱动的连带效应

```
驱动升级
    ├── Container Toolkit → 需要重装或升级
    └── Fabric Manager → 需要同步升级（最容易忘）
```

**规则：** 驱动版本 = N 时，以下所有组件都必须是 N：
- 驱动本身
- Fabric Manager
- Container Toolkit（兼容范围略宽，但最好匹配）

### 直觉 3：报错分级

```
🚨 致命：服务起不来 → 需要立刻解决（前三关）
⚠️  警告：sub-optimal → 记录，但继续推进
💡 提示：建议类信息 → 忽略，以后优化
```

---

## 离线部署物料清单

> 下次就不用临时找包了，提前备好。

```
📦 nvidia-driver-local-repo-<version>.run
📦 nvidia-fabricmanager-<version>.deb
📦 nvidia-container-tooltyk.deb
📦 deepseek-v4-flash-fp8 镜像（SGLang 格式）
```

**一句话总结：** GPU 部署的本质是**版本对齐游戏**——驱动、CUDA、Toolkit、Fabric Manager，四个版本要形成一个兼容链条，差一环都不行。
