export class HeartbeatLease {
  constructor({
    timeoutMs,
    suspendGapMs,
    now = Date.now(),
  }) {
    if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) throw new Error("心跳超时必须为正数");
    if (!Number.isFinite(suspendGapMs) || suspendGapMs <= 0) throw new Error("休眠间隔必须为正数");
    this.timeoutMs = timeoutMs;
    this.suspendGapMs = suspendGapMs;
    this.lastHeartbeatAt = now;
    this.lastTickAt = now;
  }

  heartbeat(now = Date.now()) {
    this.lastHeartbeatAt = now;
  }

  tick(now = Date.now()) {
    const tickGap = now - this.lastTickAt;
    this.lastTickAt = now;
    // 系统休眠会同时暂停浏览器心跳和 Node 事件循环。唤醒后先续租一次，
    // 避免把休眠时长误判为浏览器已经关闭。
    if (tickGap < 0 || tickGap > this.suspendGapMs) {
      this.lastHeartbeatAt = now;
      return "suspended";
    }
    return now - this.lastHeartbeatAt > this.timeoutMs ? "expired" : "active";
  }
}
