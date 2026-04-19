# Pixelize Models

Drop-in location for `script/pixelize --rembg` to find the U²-Net background-removal model without hitting the network.

## What goes here

| File | Size | Purpose |
|---|---|---|
| `u2net.onnx` | ~176 MB | Weights for the [U²-Net](https://github.com/xuebinqin/U-2-Net) salient-object-detection model, used by `rembg` for `--rembg` background removal. |

Not checked into git — too big for our LFS quota (GitHub free tier is 1 GB storage + 1 GB bandwidth/month, and a 176 MB file eats 17 % of that per fresh clone).

## How to get the file

**Option A — let rembg download it for you (easiest).**

The first time you run `script/pixelize --rembg ...` with `rembg` installed, it fetches `u2net.onnx` into `~/.u2net/` automatically and verifies the MD5. No action needed from you.

If you'd like it here instead of `~/.u2net/` (so it's discoverable alongside the tool that uses it), copy it after the first run:

```sh
cp ~/.u2net/u2net.onnx script/pixelize_models/u2net.onnx
```

The script checks this directory first and sets `U2NET_HOME` to skip the download on subsequent runs.

**Option B — manual download + hash check.**

```sh
curl -L -o script/pixelize_models/u2net.onnx \
  https://github.com/danielgatis/rembg/releases/download/v0.0.0/u2net.onnx
echo "60024c5c889badc19c04ad937298a77b  script/pixelize_models/u2net.onnx" | md5sum -c
```

Expected MD5: `60024c5c889badc19c04ad937298a77b`.

## Why the URL says `v0.0.0`

That tripped us up too. It's a [rembg](https://github.com/danielgatis/rembg) convention, not a pre-release or a mistake — rembg uses a single pinned GitHub Release tag (`v0.0.0`) as a stable CDN for **all 14 of its model weights** (u2net, u2netp, silueta, birefnet_*, dis_*, bria_rmbg, etc.). Every model's download URL points at the same `v0.0.0` release. Unconventional, but deliberate and consistent. You can grep any installed rembg to confirm:

```sh
grep -r "releases/download/v0.0.0" <rembg-install-path>/sessions/
```

## Trust chain

- **rembg package** — 22.6 k stars on GitHub, MIT licensed, maintained by Daniel Gatis. PyPI listing matches the GitHub repo owner.
- **rembg pins the model hash in its source.** `rembg/sessions/u2net.py` declares `md5:60024c5c889badc19c04ad937298a77b`. When the download happens, `pooch` verifies the hash before handing the file to rembg — tampered downloads are rejected automatically (unless `MODEL_CHECKSUM_DISABLED` is set, which we never do).
- **Underlying architecture** — U²-Net is peer-reviewed academic work: Qin et al., *Pattern Recognition* (2020), 2022 Best Paper Award. 9.7 k stars on `xuebinqin/U-2-Net`. Not a random hobbyist model.
- **Single-maintainer caveat** — if Daniel's GitHub account is ever compromised, a new rembg release could ship a different hash pointing at a different file. Defense in depth: pin `rembg==<exact-version>` in any setup docs so the hash is pinned transitively.

## If the file is missing

`script/pixelize --rembg` will fall through to letting rembg download it on demand. No error unless `rembg` itself isn't installed.
