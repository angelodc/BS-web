#!/usr/bin/env node
// Servidor estatico minimo para o export HTML5: sem dependencias e com os
// MIME types que o Godot 3.4 precisa (.wasm/.pck). Usado por start-local.sh
// quando SITE_MODE=static.
import http from "node:http";
import fs from "node:fs";
import path from "node:path";

const args = process.argv.slice(2);
function option(name, fallback) {
	const index = args.indexOf(name);
	return index >= 0 && args[index + 1] ? args[index + 1] : fallback;
}

const root = path.resolve(option("--root", "."));
const port = Number(option("--port", "8888"));
const host = option("--host", "127.0.0.1");

const MIME = {
	".html": "text/html; charset=utf-8",
	".js": "text/javascript; charset=utf-8",
	".css": "text/css; charset=utf-8",
	".json": "application/json; charset=utf-8",
	".wasm": "application/wasm",
	".pck": "application/octet-stream",
	".png": "image/png",
	".ico": "image/x-icon",
	".svg": "image/svg+xml",
	".webmanifest": "application/manifest+json",
};

function send(res, status, body, headers = {}) {
	res.writeHead(status, { "Cache-Control": "no-store", ...headers });
	res.end(body);
}

const server = http.createServer((req, res) => {
	let pathname;
	try {
		pathname = decodeURIComponent(new URL(req.url, "http://localhost").pathname);
	} catch {
		return send(res, 400, "Bad request");
	}

	let file = path.join(root, pathname);
	const relative = path.relative(root, file);
	if (relative.startsWith("..") || path.isAbsolute(relative)) {
		return send(res, 403, "Forbidden");
	}

	try {
		if (fs.statSync(file).isDirectory()) file = path.join(file, "index.html");
	} catch {
		return send(res, 404, "Not found");
	}

	let body;
	try {
		body = fs.readFileSync(file);
	} catch {
		return send(res, 404, "Not found");
	}

	const type = MIME[path.extname(file).toLowerCase()] || "application/octet-stream";
	send(res, 200, body, { "Content-Type": type, "Content-Length": body.length });
});

server.on("error", (error) => {
	console.error(`serve-static: ${error.message}`);
	process.exit(1);
});

server.listen(port, host, () => {
	console.log(`serve-static listening on http://${host}:${port} root=${root}`);
});

for (const signal of ["SIGINT", "SIGTERM"]) {
	process.on(signal, () => server.close(() => process.exit(0)));
}
