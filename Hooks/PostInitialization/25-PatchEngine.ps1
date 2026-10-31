#Requires -Modules Logging

# XIII's Engine.dll (patch 1.3/1.4 build, 2004-10-27) ends UGameEngine::Init with
#   Client->Viewports(0)->Exec("ToggleFullscreen"); Client->Viewports(0)->...;
# without checking Client, which is NULL in a dedicated server, so `UCC server` dies with
# "General protection fault! History: UGameEngine::Init <- UServerCommandlet::Main" right after
# "Game engine initialized".
#
# This patches a copy of Engine.dll: the first instructions of that block (RVA 0x79EA0) jump to a
# few bytes of code in the .text section's unused tail (RVA 0x16CA50) that skips both calls when
# Client is NULL. The copy is written through the merged view, so it lands in Overlay/ and Server/
# keeps the original. Only the known Engine.dll is patched; anything else is left alone.

$dll = Join-Path $Env:SERVER_ROOT 'System/Engine.dll'

$originalHash = '92839B5036C001B267F29654930FACABDEAF3AE3EBB15AC531D5C3DD0757312C'
$patchedHash  = '3BC904E971D824E4000734C4F464C126EB9B8F3D12DD0E944F9F36E0523BC710'

if ($Env:XIII_PATCH_ENGINE -in @('false', '0', 'no')) {
    Write-Log "XIII_PATCH_ENGINE is off; not patching Engine.dll"
    return
}

if (-not (Test-Path -Path $dll)) {
    Write-Log -Level Error "$dll not found; skipping Engine.dll patch"
    return
}

$hash = (Get-FileHash -Path $dll -Algorithm SHA256).Hash

if ($hash -eq $patchedHash) {
    Write-Log "Engine.dll is already patched for dedicated servers"
    return
}

if ($hash -ne $originalHash) {
    Write-Log -Level Warning "Unknown Engine.dll (sha256 $hash); not patching it. UCC server may crash in UGameEngine::Init."
    return
}

$bytes = [System.IO.File]::ReadAllBytes($dll)

# File offset = RVA for .text (VirtualAddress 0x1000 = PointerToRawData 0x1000)
$site = 0x79EA0   # mov ecx,[ebx+4Ch] / mov edx,[ecx+2Ch] / mov eax,[edx]
$cave = 0x16CA50  # zero padding after the end of .text
$back = 0x79EA8   # next original instruction
$skip = 0x79ED0   # first instruction after the two viewport calls

function Get-Rel32([int] $From, [int] $To) { [BitConverter]::GetBytes([int32]($To - $From)) }

$expected = [byte[]](0x8B, 0x4B, 0x4C, 0x8B, 0x51, 0x2C, 0x8B, 0x02)
for ($i = 0; $i -lt $expected.Length; $i++) {
    if ($bytes[$site + $i] -ne $expected[$i]) { throw "Unexpected bytes at Engine.dll+0x79EA0" }
}

[byte[]] $code = @(
    0x8B, 0x4B, 0x4C,        # mov  ecx,[ebx+4Ch]      ; Client
    0x85, 0xC9,              # test ecx,ecx
    0x74, 0x0A,              # jz   skip
    0x8B, 0x51, 0x2C,        # mov  edx,[ecx+2Ch]      ; Client->Viewports
    0x8B, 0x02,              # mov  eax,[edx]          ; Viewports(0)
    0xE9) + (Get-Rel32 ($cave + 17) $back) + @(  # jmp back
    0x83, 0xC4, 0x0C) +      # skip: add esp,0Ch       ; the pending debugf() cleanup
    @(0xE9) + (Get-Rel32 ($cave + 25) $skip)     # jmp past the viewport calls

for ($i = 0; $i -lt $code.Length; $i++) {
    if ($bytes[$cave + $i] -ne 0) { throw "Engine.dll code cave at 0x16CA50 is not empty" }
    $bytes[$cave + $i] = $code[$i]
}

[byte[]] $jump = @(0xE9) + (Get-Rel32 ($site + 5) $cave) + @(0x90, 0x90, 0x90)
[Array]::Copy($jump, 0, $bytes, $site, $jump.Length)

# Grow .text's VirtualSize over the cave so it is mapped from the file, not zero-filled
$pe       = [BitConverter]::ToInt32($bytes, 0x3C)
$sections = $pe + 24 + [BitConverter]::ToUInt16($bytes, $pe + 20)
if ([System.Text.Encoding]::ASCII.GetString($bytes, $sections, 5) -ne '.text') { throw "Engine.dll: first section is not .text" }
[Array]::Copy([BitConverter]::GetBytes([int32]($cave + $code.Length - 0x1000)), 0, $bytes, $sections + 8, 4)

[System.IO.File]::WriteAllBytes($dll, $bytes)
chown "$($Env:UID):$($Env:GID)" $dll

Write-Log "Patched Engine.dll so UCC server doesn't touch the (missing) client viewport"
