const SOF_MARKERS = new Set([
  0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7,
  0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf,
]);

export const MAX_IMAGE_BYTES = 16 * 1024 * 1024;
export const MAX_IMAGE_DIMENSION = 16384;
export const MAX_IMAGE_PIXELS = 50_000_000;

const ascii = (bytes, offset, length) =>
  String.fromCharCode(...bytes.subarray(offset, offset + length));
const uint16be = (bytes, offset) => bytes[offset] * 256 + bytes[offset + 1];
const uint16le = (bytes, offset) => bytes[offset] + bytes[offset + 1] * 256;
const uint24le = (bytes, offset) =>
  bytes[offset] + bytes[offset + 1] * 256 + bytes[offset + 2] * 65536;
const uint32be = (bytes, offset) =>
  bytes[offset] * 0x1000000 + bytes[offset + 1] * 0x10000 +
  bytes[offset + 2] * 0x100 + bytes[offset + 3];
const uint32le = (bytes, offset) =>
  bytes[offset] + bytes[offset + 1] * 0x100 + bytes[offset + 2] * 0x10000 +
  bytes[offset + 3] * 0x1000000;

function pngDimensions(bytes) {
  const signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (bytes.length < 24 || signature.some((value, index) => bytes[index] !== value) ||
      uint32be(bytes, 8) !== 13 || ascii(bytes, 12, 4) !== "IHDR") return null;
  return { width: uint32be(bytes, 16), height: uint32be(bytes, 20) };
}

function jpegDimensions(bytes) {
  if (bytes.length < 12 || bytes[0] !== 0xff || bytes[1] !== 0xd8) return null;
  let offset = 2;
  while (offset + 9 < bytes.length) {
    if (bytes[offset] !== 0xff) {
      offset += 1;
      continue;
    }
    while (offset < bytes.length && bytes[offset] === 0xff) offset += 1;
    const marker = bytes[offset++];
    if (marker === 0xd9 || marker === 0xda) break;
    if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd8)) continue;
    if (offset + 2 > bytes.length) break;
    const length = uint16be(bytes, offset);
    if (length < 2 || offset + length > bytes.length) break;
    if (SOF_MARKERS.has(marker) && length >= 7) {
      return {
        width: uint16be(bytes, offset + 5),
        height: uint16be(bytes, offset + 3),
      };
    }
    offset += length;
  }
  return null;
}

function webpDimensions(bytes) {
  if (bytes.length < 20 || ascii(bytes, 0, 4) !== "RIFF" ||
      ascii(bytes, 8, 4) !== "WEBP") return null;
  const riffEnd = Math.min(bytes.length, uint32le(bytes, 4) + 8);
  let offset = 12;
  while (offset + 8 <= riffEnd) {
    const type = ascii(bytes, offset, 4);
    const size = uint32le(bytes, offset + 4);
    const data = offset + 8;
    if (data + size > riffEnd) break;
    if (type === "VP8X" && size >= 10) {
      return {
        width: uint24le(bytes, data + 4) + 1,
        height: uint24le(bytes, data + 7) + 1,
      };
    }
    if (type === "VP8L" && size >= 5 && bytes[data] === 0x2f) {
      return {
        width: 1 + bytes[data + 1] + ((bytes[data + 2] & 0x3f) << 8),
        height: 1 + (bytes[data + 2] >> 6) + (bytes[data + 3] << 2) +
          ((bytes[data + 4] & 0x0f) << 10),
      };
    }
    if (type === "VP8 " && size >= 10 && bytes[data + 3] === 0x9d &&
        bytes[data + 4] === 0x01 && bytes[data + 5] === 0x2a) {
      return {
        width: uint16le(bytes, data + 6) & 0x3fff,
        height: uint16le(bytes, data + 8) & 0x3fff,
      };
    }
    offset = data + size + (size % 2);
  }
  return null;
}

export function classifyImage(bytes, extension = "") {
  if (!(bytes instanceof Uint8Array) || bytes.length < 1 || bytes.length > MAX_IMAGE_BYTES) {
    return null;
  }
  const normalized = extension.toLowerCase();
  let dimensions = null;
  let format = null;
  if (normalized === ".png" || bytes[0] === 0x89) {
    dimensions = pngDimensions(bytes);
    format = dimensions ? "png" : null;
  } else if (normalized === ".jpg" || normalized === ".jpeg" ||
      (bytes[0] === 0xff && bytes[1] === 0xd8)) {
    dimensions = jpegDimensions(bytes);
    format = dimensions ? "jpeg" : null;
  } else if (normalized === ".webp" || (bytes.length >= 12 && ascii(bytes, 8, 4) === "WEBP")) {
    dimensions = webpDimensions(bytes);
    format = dimensions ? "webp" : null;
  }
  if (!dimensions || !Number.isSafeInteger(dimensions.width) ||
      !Number.isSafeInteger(dimensions.height) || dimensions.width < 1 ||
      dimensions.height < 1 || dimensions.width > MAX_IMAGE_DIMENSION ||
      dimensions.height > MAX_IMAGE_DIMENSION ||
      dimensions.width * dimensions.height > MAX_IMAGE_PIXELS) return null;
  return { ...dimensions, format };
}
