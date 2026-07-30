import test from "node:test";
import assert from "node:assert/strict";
import {
  CONNECTION_ERROR,
  requestBlob,
  requestJson,
} from "./api-client.mjs";

test("网络连接异常转换为可操作的中文提示", async () => {
  const fetchImpl = async () => { throw new TypeError("Failed to fetch"); };
  await assert.rejects(
    requestJson(fetchImpl, "token", "/api/bootstrap"),
    { message: CONNECTION_ERROR },
  );
  await assert.rejects(
    requestBlob(fetchImpl, "token", "/api/themes/id/thumbnail"),
    { message: CONNECTION_ERROR },
  );
});

test("HTTP 与服务端业务错误保留具体信息", async () => {
  const businessError = async () => new Response(
    JSON.stringify({ ok: false, error: "主题不存在" }),
    { status: 404, headers: { "Content-Type": "application/json" } },
  );
  await assert.rejects(
    requestJson(businessError, "token", "/api/themes/missing"),
    { message: "主题不存在" },
  );

  const imageError = async () => new Response("", { status: 403 });
  await assert.rejects(
    requestBlob(imageError, "token", "/api/themes/id/thumbnail"),
    { message: "主题缩略图读取失败：403" },
  );
});

test("请求封装保留认证头并返回 JSON 或 Blob", async () => {
  const calls = [];
  const fetchImpl = async (path, options) => {
    calls.push({ path, options });
    return path.endsWith("thumbnail")
      ? new Response(new Blob(["image"]), { status: 200 })
      : new Response(JSON.stringify({ ok: true, value: 1 }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
  };
  assert.deepEqual(await requestJson(fetchImpl, "secret", "/api/bootstrap"), { ok: true, value: 1 });
  assert.equal((await requestBlob(fetchImpl, "secret", "/api/themes/id/thumbnail")).size, 5);
  assert.equal(calls[0].options.headers.Authorization, "Bearer secret");
});
