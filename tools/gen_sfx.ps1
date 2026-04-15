Add-Type @'
using System;
using System.IO;

public class WavGen {
    public const int SR = 44100;

    public static double[] Tone(double freq, double dur, double amp = 0.5,
                                double atk = 0.005, double rel = 0.02) {
        int n = (int)(dur * SR);
        int atkN = Math.Max(1, (int)(atk * SR));
        int relN = Math.Max(1, (int)(rel * SR));
        double[] s = new double[n];
        for (int i = 0; i < n; i++) {
            double t = (double)i / SR;
            double env = 1.0;
            if (i < atkN) env = (double)i / atkN;
            else if (i >= n - relN) env = (double)(n - i) / relN;
            s[i] = amp * env * Math.Sin(2.0 * Math.PI * freq * t);
        }
        return s;
    }

    public static double[] ExpDecay(double freq, double dur, double decay = 15.0, double amp = 0.55) {
        int n = (int)(dur * SR);
        double[] s = new double[n];
        for (int i = 0; i < n; i++) {
            double t = (double)i / SR;
            s[i] = amp * Math.Exp(-decay * t) * Math.Sin(2.0 * Math.PI * freq * t);
        }
        return s;
    }

    public static double[] Silence(double dur) {
        return new double[(int)(dur * SR)];
    }

    public static double[] Cat(double[][] parts) {
        int len = 0;
        foreach (var p in parts) len += p.Length;
        double[] r = new double[len];
        int off = 0;
        foreach (var p in parts) { Array.Copy(p, 0, r, off, p.Length); off += p.Length; }
        return r;
    }

    public static void MixInto(double[] dst, double[] src, int offset) {
        int end = Math.Min(src.Length, dst.Length - offset);
        for (int i = 0; i < end; i++) dst[i + offset] += src[i];
    }

    public static void Normalize(double[] s, double peak) {
        double max = 0;
        foreach (var v in s) { double a = Math.Abs(v); if (a > max) max = a; }
        if (max > 0.001) {
            double sc = peak / max;
            for (int i = 0; i < s.Length; i++) s[i] *= sc;
        }
    }

    public static void SaveWav(string path, double[] samples) {
        int dataSize = samples.Length * 2;
        using (var fs = new FileStream(path, FileMode.Create))
        using (var bw = new BinaryWriter(fs)) {
            bw.Write(new byte[]{ 82,73,70,70 });   // RIFF
            bw.Write(36 + dataSize);
            bw.Write(new byte[]{ 87,65,86,69 });   // WAVE
            bw.Write(new byte[]{ 102,109,116,32 }); // fmt
            bw.Write(16);
            bw.Write((short)1);   // PCM
            bw.Write((short)1);   // mono
            bw.Write(SR);
            bw.Write(SR * 2);
            bw.Write((short)2);
            bw.Write((short)16);
            bw.Write(new byte[]{ 100,97,116,97 }); // data
            bw.Write(dataSize);
            foreach (var v in samples) {
                double c = v < -1 ? -1 : v > 1 ? 1 : v;
                bw.Write((short)Math.Round(c * 32767));
            }
        }
        int ms = (int)Math.Round(samples.Length * 1000.0 / SR);
        Console.WriteLine("  OK  " + Path.GetFileName(path) + "  (" + ms + "ms)");
    }
}
'@

$out = 'd:\Github\ta\assets\audio\sfx'

# ── S-11: sfx_order_filled — 2-pulse blip (250Hz + 280Hz, 200ms) ──
$b1  = [WavGen]::Tone(250, 0.08, 0.60, 0.003, 0.015)
$b2  = [WavGen]::Tone(280, 0.08, 0.60, 0.003, 0.015)
$s11 = [WavGen]::Cat(@($b1, [WavGen]::Silence(0.04), $b2))
[WavGen]::Normalize($s11, 0.80)
[WavGen]::SaveWav("$out\sfx_order_filled.wav", $s11)

# ── S-13: sfx_vi_alert — 2-tone ascending warning (880 -> 1175Hz, 340ms) ──
$a1  = [WavGen]::Tone(880.0,  0.12, 0.65, 0.004, 0.015)
$a2  = [WavGen]::Tone(1174.7, 0.20, 0.65, 0.004, 0.030)
$s13 = [WavGen]::Cat(@($a1, [WavGen]::Silence(0.02), $a2))
[WavGen]::Normalize($s13, 0.88)
[WavGen]::SaveWav("$out\sfx_vi_alert.wav", $s13)

# ── S-14: sfx_news_alert — 2-note descending soft (440 -> 330Hz, 250ms) ──
$d1  = [WavGen]::Tone(440, 0.10, 0.38, 0.005, 0.020)
$d2  = [WavGen]::Tone(330, 0.14, 0.38, 0.005, 0.035)
$s14 = [WavGen]::Cat(@($d1, [WavGen]::Silence(0.01), $d2))
[WavGen]::Normalize($s14, 0.65)
[WavGen]::SaveWav("$out\sfx_news_alert.wav", $s14)

# ── S-08: sfx_profit_medium — coin cascade + C5-E5-G5 jingle (~0.9s) ──
$buf8 = New-Object double[] ([int](0.9 * [WavGen]::SR))
[WavGen]::MixInto($buf8, [WavGen]::ExpDecay(880,  0.20, 14, 0.50), 0)
[WavGen]::MixInto($buf8, [WavGen]::ExpDecay(1047, 0.20, 12, 0.50), [int](0.06 * [WavGen]::SR))
[WavGen]::MixInto($buf8, [WavGen]::ExpDecay(1319, 0.20, 10, 0.50), [int](0.12 * [WavGen]::SR))
$j1     = [WavGen]::Tone(523.25, 0.13, 0.45, 0.005, 0.020)
$j2     = [WavGen]::Tone(659.25, 0.13, 0.45, 0.005, 0.020)
$j3     = [WavGen]::Tone(783.99, 0.20, 0.45, 0.005, 0.060)
$jingle = [WavGen]::Cat(@($j1, $j2, $j3))
[WavGen]::MixInto($buf8, $jingle, [int](0.28 * [WavGen]::SR))
[WavGen]::Normalize($buf8, 0.82)
[WavGen]::SaveWav("$out\sfx_profit_medium.wav", $buf8)

# ── S-09: sfx_profit_large — 4-note fanfare C4-E4-G4-C5 (~1.0s) ──
$fn1 = [WavGen]::Tone(261.63, 0.20, 0.55, 0.006, 0.030)
$fn2 = [WavGen]::Tone(329.63, 0.20, 0.55, 0.006, 0.030)
$fn3 = [WavGen]::Tone(392.00, 0.20, 0.55, 0.006, 0.030)
$fn4 = [WavGen]::Tone(523.25, 0.40, 0.55, 0.006, 0.080)
$s09 = [WavGen]::Cat(@($fn1, $fn2, $fn3, $fn4))
[WavGen]::Normalize($s09, 0.82)
[WavGen]::SaveWav("$out\sfx_profit_large.wav", $s09)

# ── S-10: sfx_profit_jackpot — coin cascade + fanfare + final chord (~2.8s) ──
$buf10     = New-Object double[] ([int](2.8 * [WavGen]::SR))
$coinFreqs = @(700, 850, 1000, 1200, 950)
for ($ci = 0; $ci -lt 5; $ci++) {
    [WavGen]::MixInto($buf10, [WavGen]::ExpDecay($coinFreqs[$ci], 0.25, 11, 0.40),
                      [int]($ci * 0.09 * [WavGen]::SR))
}
$ff1     = [WavGen]::Tone(261.63, 0.18, 0.50, 0.005, 0.025)
$ff2     = [WavGen]::Tone(329.63, 0.18, 0.50, 0.005, 0.025)
$ff3     = [WavGen]::Tone(392.00, 0.18, 0.50, 0.005, 0.025)
$ff4     = [WavGen]::Tone(523.25, 0.18, 0.50, 0.005, 0.025)
$ff5     = [WavGen]::Tone(659.25, 0.22, 0.50, 0.005, 0.040)
$fanfare = [WavGen]::Cat(@($ff1, $ff2, $ff3, $ff4, $ff5))
[WavGen]::MixInto($buf10, $fanfare, [int](0.55 * [WavGen]::SR))
$chordLen = [int](0.70 * [WavGen]::SR)
$chord    = New-Object double[] $chordLen
foreach ($f in @(261.63, 329.63, 392.00, 523.25)) {
    [WavGen]::MixInto($chord, [WavGen]::Tone($f, 0.70, 0.28, 0.008, 0.120), 0)
}
[WavGen]::MixInto($buf10, $chord, [int](1.65 * [WavGen]::SR))
[WavGen]::Normalize($buf10, 0.85)
[WavGen]::SaveWav("$out\sfx_profit_jackpot.wav", $buf10)

Write-Host ""
Write-Host "완료. 총 6개 WAV 생성됨."
