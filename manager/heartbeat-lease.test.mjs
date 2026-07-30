import test from "node:test";
import assert from "node:assert/strict";
import { HeartbeatLease } from "./heartbeat-lease.mjs";

test("正常缺少心跳时租约按原超时边界失效", () => {
  const lease = new HeartbeatLease({ timeoutMs: 120_000, suspendGapMs: 15_000, now: 0 });
  for (let now = 5_000; now <= 120_000; now += 5_000) {
    assert.equal(lease.tick(now), "active");
  }
  assert.equal(lease.tick(125_000), "expired");
});

test("连续正常调度且没有心跳时租约失效", () => {
  const lease = new HeartbeatLease({ timeoutMs: 20_000, suspendGapMs: 6_000, now: 0 });
  assert.equal(lease.tick(5_000), "active");
  assert.equal(lease.tick(10_000), "active");
  assert.equal(lease.tick(15_000), "active");
  assert.equal(lease.tick(20_000), "active");
  assert.equal(lease.tick(25_000), "expired");
});

test("系统休眠造成的长调度间隔会续租完整心跳窗口", () => {
  const lease = new HeartbeatLease({ timeoutMs: 120_000, suspendGapMs: 15_000, now: 0 });
  assert.equal(lease.tick(5_000), "active");
  assert.equal(lease.tick(190_000), "suspended");
  for (let now = 195_000; now <= 310_000; now += 5_000) {
    assert.equal(lease.tick(now), "active");
  }
  assert.equal(lease.tick(315_000), "expired");
});

test("收到认证心跳会刷新租约", () => {
  const lease = new HeartbeatLease({ timeoutMs: 20_000, suspendGapMs: 6_000, now: 0 });
  assert.equal(lease.tick(5_000), "active");
  lease.heartbeat(10_000);
  assert.equal(lease.tick(10_000), "active");
  assert.equal(lease.tick(15_000), "active");
  assert.equal(lease.tick(20_000), "active");
  assert.equal(lease.tick(25_000), "active");
  assert.equal(lease.tick(30_000), "active");
  assert.equal(lease.tick(35_000), "expired");
});
