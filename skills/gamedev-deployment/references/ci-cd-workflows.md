# CI/CD Workflows — Game Deployment and Live Operations

## Export Preset Configuration

### PC Export (Windows / Linux / macOS)

```ini
[preset.0]
name="Windows Desktop"
platform="Windows Desktop"
runnable=true
export_filter="all_resources"
include_filter="*.import,*.tres,*.tscn"
exclude_filter="*.md,*.txt,test/*,addons/gut/*"

[preset.0.options]
binary_format/architecture="x86_64"
application/icon="res://icon.ico"
application/file_version="1.2.3.1847"
application/product_version="1.2.3.1847"
codesign/enable=true
```

### Web Export

```ini
[preset.1]
name="Web"
platform="Web"
export_filter="all_resources"
exclude_filter="*.md,test/*"

[preset.1.options]
html/export_icon=true
html/custom_html_shell="res://export/web_shell.html"
variant/extensions=false
progressive_web_app/enabled=true
progressive_web_app/offline_page="res://export/offline.html"
```

### Android Export

```ini
[preset.2]
name="Android"
platform="Android"
export_filter="all_resources"

[preset.2.options]
gradle_build/use_gradle_build=true
package/unique_name="com.studio.gamename"
version/code=1847
version/name="1.2.3"
screen/orientation="landscape"
```

### Headless Server Export

```ini
[preset.3]
name="Headless Server"
platform="Linux/X11"
export_filter="customized"
include_filter="*.gd,*.tres,*.cfg,server/*"
exclude_filter="assets/sprites/*,assets/audio/*,assets/ui/*,*.png,*.ogg,*.wav"

[preset.3.options]
binary_format/architecture="x86_64"
```

## GitHub Actions Build and Deploy Workflow

```yaml
name: Build and Export
on:
  push:
    tags: ["v*"]
  workflow_dispatch:
    inputs:
      version:
        description: "Version override (e.g., 1.2.3)"
        required: false

env:
  GODOT_VERSION: "4.4.1"
  EXPORT_NAME: "my-game"

jobs:
  version:
    runs-on: ubuntu-latest
    outputs:
      version: ${{ steps.version.outputs.version }}
      build_number: ${{ github.run_number }}
    steps:
      - name: Determine version
        id: version
        run: |
          if [ -n "${{ inputs.version }}" ]; then
            echo "version=${{ inputs.version }}" >> "$GITHUB_OUTPUT"
          elif [[ "$GITHUB_REF" == refs/tags/v* ]]; then
            echo "version=${GITHUB_REF#refs/tags/v}" >> "$GITHUB_OUTPUT"
          else
            echo "version=0.0.0-dev" >> "$GITHUB_OUTPUT"
          fi

  export:
    needs: version
    strategy:
      matrix:
        include:
          - platform: windows
            preset: "Windows Desktop"
            extension: ".exe"
            runner: ubuntu-latest
          - platform: linux
            preset: "Linux"
            extension: ""
            runner: ubuntu-latest
          - platform: macos
            preset: "macOS"
            extension: ".dmg"
            runner: macos-latest
          - platform: web
            preset: "Web"
            extension: ".html"
            runner: ubuntu-latest
    runs-on: ${{ matrix.runner }}
    steps:
      - uses: actions/checkout@v4
        with:
          lfs: true

      - name: Setup Godot
        uses: chickensoft-games/setup-godot@v2
        with:
          version: ${{ env.GODOT_VERSION }}

      - name: Stamp version
        run: |
          VERSION="${{ needs.version.outputs.version }}"
          BUILD="${{ needs.version.outputs.build_number }}"
          sed -i "s/const VERSION.*/const VERSION := \"${VERSION}\"/" version.gd
          sed -i "s/const BUILD.*/const BUILD := ${BUILD}/" version.gd

      - name: Import assets
        run: godot --headless --import

      - name: Export ${{ matrix.platform }}
        run: |
          mkdir -p build/${{ matrix.platform }}
          godot --headless --export-release \
            "${{ matrix.preset }}" \
            "build/${{ matrix.platform }}/${{ env.EXPORT_NAME }}${{ matrix.extension }}"

      - uses: actions/upload-artifact@v4
        with:
          name: ${{ matrix.platform }}-build
          path: build/${{ matrix.platform }}/

  deploy-steam:
    needs: [version, export]
    if: startsWith(github.ref, 'refs/tags/v')
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v4
        with:
          path: builds/

      - name: Deploy to Steam
        uses: game-ci/steam-deploy@v3
        with:
          username: ${{ secrets.STEAM_USERNAME }}
          configVdf: ${{ secrets.STEAM_CONFIG_VDF }}
          appId: ${{ secrets.STEAM_APP_ID }}
          buildDescription: "v${{ needs.version.outputs.version }}+${{ needs.version.outputs.build_number }}"
          rootPath: builds/
          depot1Path: windows-build/
          depot2Path: linux-build/
          depot3Path: macos-build/
          releaseBranch: beta

  deploy-web:
    needs: [version, export]
    if: startsWith(github.ref, 'refs/tags/v')
    runs-on: ubuntu-latest
    steps:
      - uses: actions/download-artifact@v4
        with:
          name: web-build
          path: build/web/

      - name: Deploy to itch.io
        uses: manleydev/butler-publish-itchio-action@v1
        env:
          BUTLER_CREDENTIALS: ${{ secrets.BUTLER_API_KEY }}
          CHANNEL: html5
          ITCH_GAME: ${{ secrets.ITCH_GAME }}
          ITCH_USER: ${{ secrets.ITCH_USER }}
          PACKAGE: build/web/
          VERSION: ${{ needs.version.outputs.version }}
```

## Automated Testing in CI

```yaml
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: chickensoft-games/setup-godot@v2
        with:
          version: ${{ env.GODOT_VERSION }}
      - name: Run tests
        run: godot --headless -s addons/gut/gut_cmdln.gd -gexit
```

## Build Info Resource Template

```
# build_info.tres — generated by CI, do not edit
[gd_resource type="Resource" script_class="BuildInfo"]
[resource]
version = "1.2.3"
build_number = 1847
commit_hash = "a1b2c3d"
build_date = "2026-03-12T10:00:00Z"
branch = "main"
```
