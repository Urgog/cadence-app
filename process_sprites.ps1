Add-Type -AssemblyName System.Drawing
$baseDir = "G:\T$([char]0x00e9)l$([char]0x00e9)chargements\Claude"
$htmlFile = "$baseDir\index.html"

# ── Crop, bg-remove, trim, encode ────────────────────────────────────────────

function Crop([System.Drawing.Bitmap]$src,[int]$x,[int]$y,[int]$w,[int]$h){
    $dst=New-Object System.Drawing.Bitmap($w,$h)
    $g=[System.Drawing.Graphics]::FromImage($dst)
    $g.DrawImage($src,(New-Object System.Drawing.Rectangle(0,0,$w,$h)),
                      (New-Object System.Drawing.Rectangle($x,$y,$w,$h)),
                      [System.Drawing.GraphicsUnit]::Pixel)
    $g.Dispose();return $dst
}

function To32([System.Drawing.Bitmap]$src){
    $fmt=[System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    $dst=New-Object System.Drawing.Bitmap($src.Width,$src.Height,$fmt)
    $g=[System.Drawing.Graphics]::FromImage($dst)
    $g.DrawImage($src,0,0,$src.Width,$src.Height);$g.Dispose();return $dst
}

function ReadPx([System.Drawing.Bitmap]$src){
    $bmp=To32 $src
    $fmt=[System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    $rect=New-Object System.Drawing.Rectangle(0,0,$bmp.Width,$bmp.Height)
    $bd=$bmp.LockBits($rect,[System.Drawing.Imaging.ImageLockMode]::ReadOnly,$fmt)
    $stride=[Math]::Abs($bd.Stride)
    $arr=[System.Array]::CreateInstance([byte],($stride*$bmp.Height))
    [System.Runtime.InteropServices.Marshal]::Copy($bd.Scan0,$arr,0,$arr.Length)
    $bmp.UnlockBits($bd);$bmp.Dispose()
    return @{a=$arr;s=$stride;w=$src.Width;h=$src.Height}
}

function RemoveBG($px,[bool]$black,[int]$t=30){
    $a=$px.a;$s=$px.s;$w=$px.w;$h=$px.h
    $fmt=[System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    $out=New-Object System.Drawing.Bitmap($w,$h,$fmt)
    $rect=New-Object System.Drawing.Rectangle(0,0,$w,$h)
    $bd=$out.LockBits($rect,[System.Drawing.Imaging.ImageLockMode]::WriteOnly,$fmt)
    $ds=[Math]::Abs($bd.Stride);$dst=[System.Array]::CreateInstance([byte],($ds*$h))
    for($y=0;$y-lt$h;$y++){for($x=0;$x-lt$w;$x++){
        $si=$y*$s+$x*4;$di=$y*$ds+$x*4
        $B=$a[$si];$G=$a[$si+1];$R=$a[$si+2];$AL=$a[$si+3]
        $bg=if($black){$R-lt$t-and$G-lt$t-and$B-lt$t}else{$R-gt(255-$t)-and$G-gt(255-$t)-and$B-gt(255-$t)}
        if($bg){$dst[$di]=0;$dst[$di+1]=0;$dst[$di+2]=0;$dst[$di+3]=0}
        else{$dst[$di]=$B;$dst[$di+1]=$G;$dst[$di+2]=$R;$dst[$di+3]=$AL}
    }}
    [System.Runtime.InteropServices.Marshal]::Copy($dst,0,$bd.Scan0,$dst.Length)
    $out.UnlockBits($bd);return $out
}

function TrimBmp([System.Drawing.Bitmap]$src){
    $px=ReadPx $src;$a=$px.a;$s=$px.s;$w=$px.w;$h=$px.h
    $x0=$w;$x1=0;$y0=$h;$y1=0
    for($y=0;$y-lt$h;$y++){for($x=0;$x-lt$w;$x++){
        if($a[$y*$s+$x*4+3]-gt10){
            if($x-lt$x0){$x0=$x};if($x-gt$x1){$x1=$x}
            if($y-lt$y0){$y0=$y};if($y-gt$y1){$y1=$y}
        }
    }}
    if($x0-gt$x1){return $null}
    $p=3
    $lx=[Math]::Max(0,$x0-$p);$ly=[Math]::Max(0,$y0-$p)
    $lw=[Math]::Min($w-$lx,$x1-$lx+1+$p*2);$lh=[Math]::Min($h-$ly,$y1-$ly+1+$p*2)
    return Crop $src $lx $ly $lw $lh
}

function Encode([System.Drawing.Bitmap]$bmp){
    $ms=New-Object System.IO.MemoryStream
    $bmp.Save($ms,[System.Drawing.Imaging.ImageFormat]::Png)
    $b64=[Convert]::ToBase64String($ms.ToArray());$ms.Dispose()
    return "data:image/png;base64,$b64"
}

# Auto-detect column ranges within a row (threshold-based, skip thin ranges <20px)
function GetCols([System.Drawing.Bitmap]$rowBmp,[bool]$black,[int]$t=30,[float]$pct=0.95,[int]$minW=20){
    $px=ReadPx $rowBmp;$a=$px.a;$stride=$px.s;$w=$px.w;$h=$px.h
    $ranges=@();$inRange=$false;$st=0
    $minBg=[int]($h*$pct)
    for($x=0;$x-lt$w;$x++){
        $cnt=0
        for($y=0;$y-lt$h;$y++){
            $i=$y*$stride+$x*4;$B=$a[$i];$G=$a[$i+1];$R=$a[$i+2]
            if($black){if($R-lt$t-and$G-lt$t-and$B-lt$t){$cnt++}}
            else{if($R-gt(255-$t)-and$G-gt(255-$t)-and$B-gt(255-$t)){$cnt++}}
        }
        $colIsBg=($cnt-ge$minBg)
        if(-not$colIsBg-and-not$inRange){$st=$x;$inRange=$true}
        elseif($colIsBg-and$inRange){if(($x-$st)-ge$minW){$ranges+=@{S=$st;E=($x-1)}};$inRange=$false}
    }
    if($inRange-and($w-$st)-ge$minW){$ranges+=@{S=$st;E=($w-1)}}
    return $ranges
}

# Remove the stage-number label from the top of each sprite.
# Strategy 1: gap detection (label then empty rows then dragon → crop at gap end).
# Strategy 2: column-based erasure (label and dragon overlap vertically — identify
#   columns whose top rows contain only neutral/gray pixels = label, no colored dragon).
function RemoveTopLabel([System.Drawing.Bitmap]$src,[bool]$black){
    $px=ReadPx $src;$a=$px.a;$stride=$px.s;$w=$px.w;$h=$px.h

    # ── Strategy 1: gap detection ─────────────────────────────────────────────
    $scanH=[Math]::Min($h,70)
    $inContent=$false;$inGap=$false;$gapEnd=-1
    for($y=0;$y-lt$scanH;$y++){
        $hasContent=$false
        for($x=0;$x-lt$w;$x++){if($a[$y*$stride+$x*4+3]-gt10){$hasContent=$true;break}}
        if($hasContent-and-not$inContent){$inContent=$true}
        elseif(-not$hasContent-and$inContent-and-not$inGap){$inGap=$true}
        elseif($hasContent-and$inGap){$gapEnd=$y;break}
    }
    if($gapEnd-gt0){$nb=Crop $src 0 $gapEnd $w ($h-$gapEnd);return $nb}

    # ── Strategy 2: column-based neutral-pixel erasure ────────────────────────
    # For sprites where label overlaps dragon in Y (e.g. stage 9 large wings at y=0):
    # Columns whose top SCAN_TOP rows have ONLY neutral pixels are label columns → erase.
    $SCAN_TOP=[Math]::Min($h,30)
    $NEUTRAL_T=50  # max |R-G|, |G-B|, |R-B| to be considered neutral gray
    $colorCols=@{}
    for($x=0;$x-lt$w;$x++){
        for($y=0;$y-lt$SCAN_TOP;$y++){
            $si=$y*$stride+$x*4
            if($a[$si+3]-gt10){
                $B=$a[$si];$G=$a[$si+1];$R=$a[$si+2]
                $dRG=[Math]::Abs([int]$R-[int]$G)
                $dGB=[Math]::Abs([int]$G-[int]$B)
                $dRB=[Math]::Abs([int]$R-[int]$B)
                if($dRG-ge$NEUTRAL_T-or$dGB-ge$NEUTRAL_T-or$dRB-ge$NEUTRAL_T){
                    $colorCols[$x]=1;break
                }
            }
        }
    }
    $fmt=[System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    $out=New-Object System.Drawing.Bitmap($w,$h,$fmt)
    $rect=New-Object System.Drawing.Rectangle(0,0,$w,$h)
    $bd=$out.LockBits($rect,[System.Drawing.Imaging.ImageLockMode]::WriteOnly,$fmt)
    $ds=[Math]::Abs($bd.Stride)
    $dst=[System.Array]::CreateInstance([byte],($ds*$h))
    for($y=0;$y-lt$h;$y++){for($x=0;$x-lt$w;$x++){
        $si=$y*$stride+$x*4;$di=$y*$ds+$x*4
        if($y-lt$SCAN_TOP-and$a[$si+3]-gt10-and-not$colorCols.ContainsKey($x)){
            $dst[$di]=0;$dst[$di+1]=0;$dst[$di+2]=0;$dst[$di+3]=0
        } else {
            $dst[$di]=$a[$si];$dst[$di+1]=$a[$si+1];$dst[$di+2]=$a[$si+2];$dst[$di+3]=$a[$si+3]
        }
    }}
    [System.Runtime.InteropServices.Marshal]::Copy($dst,0,$bd.Scan0,$dst.Length)
    $out.UnlockBits($bd);return $out
}

function ProcessRow([System.Drawing.Bitmap]$sheet,[int]$ry,[int]$rh,[bool]$black,[int]$maxCols){
    $rowBmp=Crop $sheet 0 $ry $sheet.Width $rh
    $cols=GetCols $rowBmp $black
    Write-Host "    cols=$($cols.Count)"
    $out=@{}; $ci=0
    foreach($c in $cols){
        if($ci-ge$maxCols){break}
        $cw=$c.E-$c.S+1
        $cell=Crop $rowBmp $c.S 0 $cw $rh
        $cpx=ReadPx $cell
        # White-bg sheets need a higher threshold to remove near-white bg residuals (R=216-224)
        $thr=if($black){30}else{50}
        $clean=RemoveBG $cpx $black $thr
        $nolabel=RemoveTopLabel $clean $black
        $tr=TrimBmp $nolabel
        if($tr-and$tr.Width-gt4-and$tr.Height-gt4){
            $out[$ci]=Encode $tr
            Write-Host "      stage $($ci+1): $($tr.Width)x$($tr.Height)"
            $tr.Dispose()
        } else { Write-Host "      stage $($ci+1): empty" }
        $cell.Dispose();$clean.Dispose()
        if($nolabel-ne$clean){$nolabel.Dispose()}
        $ci++
    }
    $rowBmp.Dispose();return $out
}

# ── Init sprite arrays ────────────────────────────────────────────────────────
$names  = @("Draconnet","Luciole","Ombre","Verdur","Solarius")
$colors = @("#E06040","#50BFFF","#9060D0","#3DB87A","#FFD700")
$sp=@{}
for($fi=0;$fi-lt5;$fi++){
    $arr=@("null","null","null","null","null","null","null","null","null")
    $sp[$fi]=$arr
}

# ── Sheet 1: dragons_couleurs.png ─────────────────────────────────────────────
# Row ranges determined by pixel scan: [yStart, height, familiarIdx]
$s1Rows = @(
    @{y=28;  h=192; fi=0},   # Red   → Draconnet
    @{y=276; h=200; fi=1},   # Blue  → Luciole
    @{y=532; h=196; fi=3},   # Green → Verdur
    @{y=792; h=212; fi=4}    # Gold  → Solarius
)

$f1="$baseDir\dragons_couleurs.png"
if(-not(Test-Path $f1)){Write-Error "Not found: $f1";exit 1}
Write-Host "`n=== dragons_couleurs.png ===" -ForegroundColor Cyan
$sh1=New-Object System.Drawing.Bitmap($f1)
Write-Host "  $($sh1.Width)x$($sh1.Height)"

foreach($row in $s1Rows){
    Write-Host "  Familiar $($row.fi) ($($names[$row.fi])) y=$($row.y) h=$($row.h):"
    $cols=ProcessRow $sh1 $row.y $row.h $true 9
    foreach($ci in $cols.Keys){$sp[$row.fi][$ci]=$cols[$ci]}
}
$sh1.Dispose()

# ── Sheet 2: dragon_violet.png ────────────────────────────────────────────────
# Row 1 (stages 1-5): y=136, h=212
# Row 2 (stages 6-9): y=432, h=384
$f2="$baseDir\dragon_violet.png"
if(-not(Test-Path $f2)){Write-Error "Not found: $f2";exit 1}
Write-Host "`n=== dragon_violet.png ===" -ForegroundColor Cyan
$sh2=New-Object System.Drawing.Bitmap($f2)
Write-Host "  $($sh2.Width)x$($sh2.Height)"

Write-Host "  Row 1 (stages 1-5) y=136 h=212:"
$r1=ProcessRow $sh2 136 212 $false 5
for($ci=0;$ci-lt5;$ci++){if($r1.ContainsKey($ci)){$sp[2][$ci]=$r1[$ci]}}

Write-Host "  Row 2 (stages 6-9) y=432 h=384:"
$r2=ProcessRow $sh2 432 384 $false 4
for($ci=0;$ci-lt4;$ci++){if($r2.ContainsKey($ci)){$sp[2][$ci+5]=$r2[$ci]}}

$sh2.Dispose()

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host "`n=== Summary ===" -ForegroundColor Yellow
for($fi=0;$fi-lt5;$fi++){
    $ok=($sp[$fi]|Where-Object{$_-ne"null"}).Count
    Write-Host "  [$fi] $($names[$fi]): $ok/9"
}

# ── Build FAMILIAR_DATA ───────────────────────────────────────────────────────
$sb=New-Object System.Text.StringBuilder
[void]$sb.AppendLine("const FAMILIAR_DATA = [")
for($fi=0;$fi-lt5;$fi++){
    $parts=for($s=0;$s-lt9;$s++){if($sp[$fi][$s]-eq"null"){"null"}else{'"'+$sp[$fi][$s]+'"'}}
    [void]$sb.Append("  { name: `"$($names[$fi])`",  color: `"$($colors[$fi])`", sprites: [")
    [void]$sb.Append(($parts-join","))
    [void]$sb.AppendLine("] },")
}
[void]$sb.Append("];")
$newBlock=$sb.ToString()

# ── Patch index.html ──────────────────────────────────────────────────────────
Write-Host "`n=== Patching index.html ===" -ForegroundColor Green
$html=[System.IO.File]::ReadAllText($htmlFile,[System.Text.Encoding]::UTF8)
$opts=[System.Text.RegularExpressions.RegexOptions]::Singleline
$pat='const FAMILIAR_DATA = \[[\s\S]*?\];'
if([regex]::IsMatch($html,$pat,$opts)){
    $html=[regex]::Replace($html,$pat,$newBlock,$opts)
    [System.IO.File]::WriteAllText($htmlFile,$html,[System.Text.Encoding]::UTF8)
    Write-Host "  index.html updated!" -ForegroundColor Green
} else {
    Write-Warning "Pattern not found"
    [System.IO.File]::WriteAllText("$baseDir\sprites_patch.js",$newBlock,[System.Text.Encoding]::UTF8)
    Write-Host "  Fallback: sprites_patch.js"
}
