const assert = require("node:assert/strict")
const fs = require("node:fs")
const os = require("node:os")
const path = require("node:path")
const test = require("node:test")
const { spawnSync } = require("node:child_process")

const root = path.join(__dirname, "..")
const installer = path.join(root, "scripts", "install-cli")
const signingKey = path.join(root, "assets", "windscribe-linux-signing-key.asc")

function stableRelease(id, version, build, url, sha256) {
  return {
    id,
    integration: "ws",
    type: "desktop",
    platform: "linux_zst_x64_cli",
    version,
    build,
    beta: 0,
    url,
    is_supported: 1,
    upgradable: 1,
    force_upgrade: 0,
    sha256,
  }
}

test("installer pins the trust key and verifies before pacman", () => {
  fs.accessSync(installer, fs.constants.X_OK)
  const source = fs.readFileSync(installer, "utf8")
  const vpnState = fs.readFileSync(path.join(root, "VpnState.qml"), "utf8")

  assert.match(source, /api\.windscribe\.com\/ChangeLogs\?platform=linux_zst_x64_cli/)
  assert.match(source, /Authorization: Bearer 0/)
  assert.match(source, /\.beta == 0/)
  assert.match(source, /\.is_supported == 1/)
  assert.match(source, /\.upgradable == 1/)
  assert.match(source, /deploy\\\.totallyacdn\\\.com/)
  assert.match(source, /\$\{release_url\}\.sig/)
  assert.match(source, /441B49B9D5AFCCAC158444F4E699B988472B0781/)
  assert.match(source, /495B477E0F3FA67C20ED94B2BD09F61D249A38FA/)
  assert.match(source, /sha256sum -- "\$package"/)
  assert.match(source, /gpgv --homedir/)
  assert.match(source, /metadata_limit=1048576/)
  assert.match(source, /--max-filesize "\$package_limit"/)
  assert.match(source, /--max-filesize "\$signature_limit"/)
  assert.match(source, /minimum_version='2\.23\.11'/)
  assert.ok(
    source.lastIndexOf("verify_package \"$package\"")
      < source.lastIndexOf("/usr/bin/sudo /usr/bin/pacman"),
  )
  assert.match(vpnState, /Qt\.resolvedUrl\("scripts\/install-cli"\)/)
  assert.match(vpnState, /Model\.shellQuote\(localFilePath\(cliInstallerUrl\)\)/)
  assert.equal(vpnState.includes("Model.cliInstallCommand()"), false)
})

test("bundled Windscribe signing key has the pinned fingerprint", (t) => {
  const probe = spawnSync("gpg", ["--version"], { encoding: "utf8" })
  if (probe.error || probe.status !== 0) {
    t.skip("gpg is unavailable")
    return
  }

  const home = fs.mkdtempSync(path.join(os.tmpdir(), "ws-key-"))
  fs.chmodSync(home, 0o700)
  try {
    const result = spawnSync(
      "gpg",
      ["--batch", "--homedir", home, "--with-colons", "--show-keys", signingKey],
      { encoding: "utf8" },
    )
    assert.equal(result.status, 0, result.stderr)
    const fingerprints = result.stdout
      .split(/\r?\n/)
      .filter((line) => line.startsWith("fpr:"))
      .map((line) => line.split(":")[9])
    assert.deepEqual(fingerprints, [
      "441B49B9D5AFCCAC158444F4E699B988472B0781",
      "495B477E0F3FA67C20ED94B2BD09F61D249A38FA",
    ])
  } finally {
    fs.rmSync(home, { recursive: true, force: true })
  }
})

test("installer selects the newest supported stable release and rejects bad metadata", (t) => {
  if (!fs.existsSync("/usr/bin/jq")) {
    t.skip("/usr/bin/jq is unavailable")
    return
  }

  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "ws-metadata-"))
  try {
    const hash = "a".repeat(64)
    const valid = stableRelease(
      200,
      "2.24",
      1,
      "https://deploy.totallyacdn.com/desktop-apps/2.24.1/windscribe-cli_2.24.1_amd64.pkg.tar.zst",
      hash,
    )
    const old = stableRelease(
      100,
      "2.23",
      11,
      "https://deploy.totallyacdn.com/desktop-apps/2.23.11/windscribe-cli_2.23.11_amd64.pkg.tar.zst",
      "b".repeat(64),
    )
    const beta = {
      ...stableRelease(
        300,
        "2.25",
        1,
        "https://deploy.totallyacdn.com/desktop-apps/2.25.1/windscribe-cli_2.25.1_amd64.pkg.tar.zst",
        "c".repeat(64),
      ),
      beta: 1,
    }
    const unsupported = {
      ...stableRelease(
        400,
        "2.26",
        1,
        "https://deploy.totallyacdn.com/desktop-apps/2.26.1/windscribe-cli_2.26.1_amd64.pkg.tar.zst",
        "d".repeat(64),
      ),
      is_supported: 0,
    }

    const metadata = path.join(tmp, "valid.json")
    fs.writeFileSync(metadata, JSON.stringify({ data: [old, beta, valid, unsupported] }))
    const selected = spawnSync(installer, ["--select-metadata", metadata], {
      encoding: "utf8",
    })
    assert.equal(selected.status, 0, selected.stderr)
    assert.equal(
      selected.stdout.trim(),
      `200\t2.24.1\t${valid.url}\t${hash}`,
    )

    const evil = {
      ...stableRelease(
        500,
        "2.27",
        1,
        "https://evil.example/windscribe-cli_2.27.1_amd64.pkg.tar.zst",
        "e".repeat(64),
      ),
    }
    const maliciousMetadata = path.join(tmp, "malicious.json")
    fs.writeFileSync(maliciousMetadata, JSON.stringify({ data: [valid, evil] }))
    const malicious = spawnSync(installer, ["--select-metadata", maliciousMetadata], {
      encoding: "utf8",
    })
    assert.equal(malicious.status, 1)
    assert.match(malicious.stderr, /outside the trusted CDN path/)

    const rollbackMetadata = path.join(tmp, "rollback.json")
    fs.writeFileSync(
      rollbackMetadata,
      JSON.stringify({
        data: [
          stableRelease(
            99,
            "2.23",
            10,
            "https://deploy.totallyacdn.com/desktop-apps/2.23.10/windscribe-cli_2.23.10_amd64.pkg.tar.zst",
            "f".repeat(64),
          ),
        ],
      }),
    )
    const rollback = spawnSync(installer, ["--select-metadata", rollbackMetadata], {
      encoding: "utf8",
    })
    assert.equal(rollback.status, 1)
    assert.match(rollback.stderr, /older than the allowed minimum/)
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true })
  }
})
