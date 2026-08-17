export const CONNECTION_ERROR =
  "管理器连接已断开，请重新打开 Codex Aurora Skin。";

async function authenticatedFetch(fetchImpl, token, path, options = {}) {
  if (!token) throw new Error("管理器链接缺少安全令牌，请重新打开 Codex Aurora Skin。");
  try {
    return await fetchImpl(path, {
      ...options,
      headers: {
        Authorization: `Bearer ${token}`,
        ...(options.body instanceof FormData ? {} : { "Content-Type": "application/json" }),
        ...options.headers,
      },
    });
  } catch {
    throw new Error(CONNECTION_ERROR);
  }
}

export async function requestJson(fetchImpl, token, path, options = {}) {
  const response = await authenticatedFetch(fetchImpl, token, path, options);
  const result = await response.json().catch(() => ({ error: `请求失败：${response.status}` }));
  if (!response.ok || result.ok === false) {
    throw new Error(result.error || `请求失败：${response.status}`);
  }
  return result;
}

export async function requestBlob(fetchImpl, token, path, options = {}) {
  const response = await authenticatedFetch(fetchImpl, token, path, options);
  if (!response.ok) throw new Error(`主题缩略图读取失败：${response.status}`);
  return response.blob();
}
