# H20 GPU 部署 DeepSeek-V4 实战笔记 🚀

> 基于 SGLang 在 8×NVIDIA H20 上离线部署 DeepSeek-V4 的**完整排障与优化记录**

## 📋 目录

- [环境概览](#环境概览)
- [部署排障全流程](#部署排障全流程)
- [性能优化](#性能优化)
- [快速排障速查表](#快速排障速查表)
- [离线部署 Checklist](#离线部署-checklist)

---

## 环境概览

| 组件 | 版本 |
|------|------|
| GPU | 8× NVIDIA H20 (NVLink互联) |
| 驱动 | 575.57.08 |
| CUDA (容器内) | 12.9.1 |
| Container Toolkit | 1.19.0 |
| Fabric Manager | 575.57.08 (与驱动一致) |
| 推理引擎 | SGLang |
| 模型 | DeepSeek-V4-Flash-FP8 |

---

## 部署排障全流程

### 🔴 第一关：Error 802 — 驱动版本过低

**症状：**
```
Error 802: system not yet initialized
CUDA initialization: Unexpected error from cudaGetDeviceCount()
```

**排障推导：**

1. 宿主机 `nvidia-smi` 能识别 8 张 H20 → ✅ 硬件没问题
2. 同一镜像别人（H800）能跑 → ❌ 差异在环境
3. 对比版本：
   - 宿主机驱动: `550.54.14`
   - 容器内 CUDA: `12.9.1`（需要驱动 ≥ 570）
4. **结论：** 驱动版本不够，升级 550 → 575

**💡 核心直觉：** 容器内的 CUDA 版本 > 宿主机驱动的支持上限 → 初始化必失败。

---

### 🟡 第二关：No Accelerator — Container Toolkit 未安装

**症状（升级驱动后）：**
```
RuntimeError: No accelerator (CUDA, XPU, HPU, NPU) is available.
```

**排障推导：**

1. `docker run --rm --gpus all ... nvidia-smi` → ✅ Docker 能看到 GPU
2. 容器内 `torch.cuda.is_available()` → ❌ **False**（PyTorch 底层调用比 nvidia-smi 更敏感）
3. `systemctl status nvidia-container-toolkit` → ❌ **Unit not found**
4. **结论：** Docker 和 NVIDIA 驱动之间缺了"桥梁"——Container Toolkit

**💡 核心直觉：** `nvidia-smi` 能跑但 PyTorch 不认 GPU → 往往是 Docker GPU 穿透机制的问题。

---

### 🟠 第三关：依然 Error 802 — Fabric Manager 版本不匹配

**症状（装完 Toolkit 后）：**
```
Error 802 依然存在
```

**排障推导：**

1. 驱动 575 ✅ | Container Toolkit 已装 ✅ | nvidia-smi 正常 ✅ → 还差什么？
2. H20 是数据中心 GPU，8 卡之间有 **NVLink/NVSwitch 互联**
3. `systemctl status nvidia-fabricmanager` → ❌ **failed**
4. 日志显示：`version 550.54.14 don't match driver version 575.57.08`
   - Fabric Manager 还是旧版的！驱动升级了它没升。
5. **结论：** 重新安装匹配 575 版本的 Fabric Manager

**💡 核心直觉：** 驱动升级后，**所有和驱动版本绑定的组件**（Fabric Manager, Container Toolkit）都要同步更新。

---

### 🟢 第四关：sub-optimal 警告 — 镜像无伤大雅

**症状（服务起来了）：**
```
Using default MoE kernel config. Performance might be sub-optimal!
```

**判断：**

1. 模型已加载，API 可调用 → ✅ 功能正常
2. `sub-optimal` 只是性能未达最优，不是报错
3. 原因是 H20 没有对应的预编译配置，降级用了通用配置
4. **处理：** 不影响使用，以后补

**💡 核心直觉：** 服务能跑起来的"报错"通常是小问题，不要在大体成功后继续钻牛角尖。

---

## 性能优化

### ⚡ 加速 SGLang 启动

#### 第 1 步：预编译 DeepGEMM 内核

```bash
# 设置缓存目录
export SGLANG_DG_CACHE_DIR=/path/to/your/cache_dir

# 预编译 DeepGEMM（参数与启动命令一致）
python -m sglang.compile_deep_gemm \
    --model /path/to/DeepSeek-V4-Flash-FP8 \
    --tp 8
```

#### 第 2 步：修改启动命令

```bash
# 指定同一缓存目录
export SGLANG_DG_CACHE_DIR=/path/to/your/cache_dir

# 添加 --enable-torch-compile 参数
python -m sglang.launch_server \
    --model-path /model \
    --served-model-name "cct-1.4" \
    --tp 8 \
    --enable-torch-compile \
    # ... 其他参数
```

**原理：** `compile_deep_gemm` 负责"预编译模型内核"，`--enable-torch-compile` 负责"加速模型图编译"，配合使用可大幅缩短 SGLang 启动时间。

---

## 快速排障速查表

| 症状 | 最先怀疑 | 核心验证命令 |
|------|----------|-------------|
| `Error 802` + 容器启动失败 | 驱动版本不够 | `nvidia-smi` 对比 CUDA 版本 |
| `No accelerator` | Docker-GPU 通道断裂 | `systemctl status nvidia-container-toolkit` |
| 装完 Toolkit 依然 802 | NVLink 组件版本不匹配 | `systemctl status nvidia-fabricmanager` |
| 启动慢 / 配置警告 | 镜像适配不全 | 看日志是否只是 sub-optimal |

---

## 离线部署 Checklist

下次离线部署前，提前备好这**三件套**，同步升级：

- [ ] **驱动 .run 文件**（版本 ≥ 容器 CUDA 要求）
- [ ] **nvidia-fabricmanager deb 包**（版本必须与驱动一致）
- [ ] **nvidia-container-toolkit deb 包**（Docker GPU 桥梁）

> **教训：** 驱动升级时，Fabric Manager 不会自动升级，这是个极易被忽略的隐藏坑。

---

*记录于 2026-04*
