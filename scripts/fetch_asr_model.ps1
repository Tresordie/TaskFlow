# Downloads the bundled SenseVoice ASR model into assets/models/sensevoice/.
#
# The ~228 MB int8 model is NOT committed to git (see .gitignore) — run this
# script once before `flutter build` / `flutter run`:
#   powershell -ExecutionPolicy Bypass -File scripts\fetch_asr_model.ps1
#
# Sources mirror the voice_transcription reference project (catalog.ts):
# sherpa-onnx official model repo, hf-mirror first (directly reachable from
# CN), huggingface.co fallback.

$ErrorActionPreference = 'Stop'

$Dir = Join-Path $PSScriptRoot '..\assets\models\sensevoice'
New-Item -ItemType Directory -Force -Path $Dir | Out-Null

$Files = @(
    @{
        Name = 'model.int8.onnx'
        Size = 239233841
        Urls = @(
            'https://hf-mirror.com/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/model.int8.onnx',
            'https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/model.int8.onnx'
        )
    },
    @{
        Name = 'tokens.txt'
        Size = 315894
        Urls = @(
            'https://hf-mirror.com/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/tokens.txt',
            'https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/tokens.txt'
        )
    }
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

foreach ($f in $Files) {
    $target = Join-Path $Dir $f.Name
    if ((Test-Path $target) -and ((Get-Item $target).Length -eq $f.Size)) {
        Write-Host "[skip] $($f.Name) already present ($($f.Size) bytes)"
        continue
    }
    $ok = $false
    foreach ($url in $f.Urls) {
        try {
            Write-Host "[get ] $($f.Name) from $url"
            Invoke-WebRequest -Uri $url -OutFile $target -UseBasicParsing
            $len = (Get-Item $target).Length
            if ($len -ne $f.Size) {
                throw "size mismatch: got $len, expected $($f.Size)"
            }
            Write-Host "[ok  ] $($f.Name) ($len bytes)"
            $ok = $true
            break
        } catch {
            Write-Warning "download failed from $url : $_"
            if (Test-Path $target) { Remove-Item $target -Force }
        }
    }
    if (-not $ok) {
        throw "Could not fetch $($f.Name). Check network access to hf-mirror.com / huggingface.co."
    }
}

Write-Host 'ASR model assets ready.'
