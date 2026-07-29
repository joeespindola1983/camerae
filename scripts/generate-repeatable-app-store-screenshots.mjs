#!/usr/bin/env node

import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const sharp = require("sharp");

if (process.argv.length !== 4) {
  console.error("Uso: generate-repeatable-app-store-screenshots.mjs INPUT_DIR OUTPUT_DIR");
  process.exit(2);
}

const [, , inputDirectory, outputDirectory] = process.argv;
const stories = [
  {
    slug: "estatuas",
    title: ["Dia e noite.", "O mesmo enquadramento."],
    subtitle: "Volte ao mesmo lugar e continue a história.",
    first: "15-50.png",
    second: "14-50.png",
  },
  {
    slug: "lagoa",
    title: ["A cena muda.", "Seu quadro permanece."],
    subtitle: "Repita a captura com a referência sempre à vista.",
    first: "09-50.png",
    second: "11-50.png",
  },
  {
    slug: "catedral",
    title: ["Grave hoje.", "Repita quando quiser."],
    subtitle: "Enquadre com precisão em cada novo momento.",
    first: "04-50.png",
    second: "00-50.png",
  },
];

const devices = [
  {
    name: "iphone",
    width: 1290,
    height: 2796,
    margin: 84,
    titleSize: 88,
    subtitleSize: 38,
    cardHeight: 800,
    cardGap: 54,
    firstTop: 600,
  },
  {
    name: "ipad",
    width: 2064,
    height: 2752,
    margin: 150,
    titleSize: 104,
    subtitleSize: 44,
    cardHeight: 800,
    cardGap: 58,
    firstTop: 650,
  },
];

const escapeXml = (value) =>
  value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");

async function card(source, width, height, radius, label, labelSize) {
  const photo = await sharp(source)
    .resize(width, height, { fit: "cover", position: "centre" })
    .png()
    .toBuffer();
  const overlay = Buffer.from(`
    <svg width="${width}" height="${height}" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <linearGradient id="shade" x1="0" y1="0" x2="0" y2="1">
          <stop offset="65%" stop-color="#000" stop-opacity="0"/>
          <stop offset="100%" stop-color="#000" stop-opacity=".70"/>
        </linearGradient>
      </defs>
      <rect width="${width}" height="${height}" fill="url(#shade)"/>
      <rect x="2" y="2" width="${width - 4}" height="${height - 4}" rx="${radius}" fill="none" stroke="#ff7134" stroke-width="4"/>
      <text x="34" y="${height - 36}" fill="#fff" font-family="Arial, sans-serif" font-weight="700" font-size="${labelSize}" letter-spacing="2">${label}</text>
    </svg>
  `);
  const mask = Buffer.from(`
    <svg width="${width}" height="${height}" xmlns="http://www.w3.org/2000/svg">
      <rect width="${width}" height="${height}" rx="${radius}" fill="#fff"/>
    </svg>
  `);
  return sharp(photo)
    .composite([{ input: overlay }, { input: mask, blend: "dest-in" }])
    .png()
    .toBuffer();
}

function copyLayer(story, device) {
  const { width, height, margin, titleSize, subtitleSize } = device;
  const pillWidth = width > 1500 ? 600 : 520;
  const pillHeight = width > 1500 ? 76 : 68;
  const pillTop = width > 1500 ? 118 : 96;
  const titleTop = width > 1500 ? 250 : 210;
  const titleLineGap = titleSize * 1.04;
  const subtitleTop = titleTop + titleLineGap * 2 + 42;
  const footerY = device.firstTop + device.cardHeight * 2 + device.cardGap + 112;
  return Buffer.from(`
    <svg width="${width}" height="${height}" xmlns="http://www.w3.org/2000/svg">
      <rect x="${margin}" y="${pillTop}" width="${pillWidth}" height="${pillHeight}" rx="${pillHeight / 2}" fill="#ff7134"/>
      <text x="${margin + pillWidth / 2}" y="${pillTop + pillHeight * .66}" text-anchor="middle" fill="#fff" font-family="Arial, sans-serif" font-weight="700" font-size="${width > 1500 ? 30 : 27}" letter-spacing="2.4">CAMERAE · REPEATABLE</text>
      <text x="${margin}" y="${titleTop + titleSize}" fill="#13110f" font-family="Arial, sans-serif" font-weight="700" font-size="${titleSize}">
        <tspan x="${margin}" dy="0">${escapeXml(story.title[0])}</tspan>
        <tspan x="${margin}" dy="${titleLineGap}">${escapeXml(story.title[1])}</tspan>
      </text>
      <text x="${margin}" y="${subtitleTop + subtitleSize}" fill="#6d5e4a" font-family="Arial, sans-serif" font-size="${subtitleSize}">${escapeXml(story.subtitle)}</text>
      <line x1="${margin}" y1="${footerY - 48}" x2="${margin + 90}" y2="${footerY - 48}" stroke="#ff7134" stroke-width="8" stroke-linecap="round"/>
      <text x="${margin}" y="${footerY}" fill="#6d5e4a" font-family="Arial, sans-serif" font-weight="600" font-size="${width > 1500 ? 30 : 26}">O mesmo enquadramento. Um novo momento.</text>
    </svg>
  `);
}

async function render(story, device) {
  const cardWidth = device.width - device.margin * 2;
  const radius = device.width > 1500 ? 44 : 38;
  const labelSize = device.width > 1500 ? 30 : 27;
  const first = await card(
    path.join(inputDirectory, story.first),
    cardWidth,
    device.cardHeight,
    radius,
    "CAPTURA 01",
    labelSize,
  );
  const second = await card(
    path.join(inputDirectory, story.second),
    cardWidth,
    device.cardHeight,
    radius,
    "CAPTURA 02",
    labelSize,
  );
  const destination = path.join(outputDirectory, device.name);
  await fs.mkdir(destination, { recursive: true });
  const filename = `repeatable-${story.slug}-${device.width}x${device.height}.png`;
  const output = path.join(destination, filename);

  await sharp({
    create: {
      width: device.width,
      height: device.height,
      channels: 3,
      background: "#f7f4ed",
    },
  })
    .composite([
      { input: copyLayer(story, device), left: 0, top: 0 },
      { input: first, left: device.margin, top: device.firstTop },
      {
        input: second,
        left: device.margin,
        top: device.firstTop + device.cardHeight + device.cardGap,
      },
    ])
    .flatten({ background: "#f7f4ed" })
    .removeAlpha()
    .png({ compressionLevel: 9 })
    .toFile(output);
  console.log(output);
}

for (const device of devices) {
  for (const story of stories) {
    await render(story, device);
  }
}
