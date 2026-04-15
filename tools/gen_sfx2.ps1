Add-Type @'
using System; using System.IO;
public class WavGen2 {
    public const int SR = 44100;
    public static double[] Tone(double freq, double dur, double amp=0.5, double atk=0.005, double rel=0.02) {
        int n=(int)(dur*SR), atkN=Math.Max(1,(int)(atk*SR)), relN=Math.Max(1,(int)(rel*SR));
        double[] s=new double[n];
        for(int i=0;i<n;i++){
            double t=(double)i/SR, e=1.0;
            if(i<atkN) e=(double)i/atkN;
            else if(i>=n-relN) e=(double)(n-i)/relN;
            s[i]=amp*e*Math.Sin(2*Math.PI*freq*t);
        }
        return s;
    }
    public static double[] ExpDecay(double freq, double dur, double decay=15, double amp=0.6) {
        int n=(int)(dur*SR); double[] s=new double[n];
        for(int i=0;i<n;i++){double t=(double)i/SR; s[i]=amp*Math.Exp(-decay*t)*Math.Sin(2*Math.PI*freq*t);}
        return s;
    }
    public static double[] Cat(double[][] p) {
        int l=0; foreach(var a in p) l+=a.Length;
        double[] r=new double[l]; int o=0;
        foreach(var a in p){Array.Copy(a,0,r,o,a.Length); o+=a.Length;} return r;
    }
    public static void MixInto(double[] dst, double[] src, int off) {
        int e=Math.Min(src.Length, dst.Length-off);
        for(int i=0;i<e;i++) dst[i+off]+=src[i];
    }
    public static void Norm(double[] s, double peak) {
        double m=0; foreach(var v in s){double a=Math.Abs(v); if(a>m)m=a;}
        if(m>0.001){double sc=peak/m; for(int i=0;i<s.Length;i++) s[i]*=sc;}
    }
    public static void Save(string path, double[] samples) {
        int ds=samples.Length*2;
        using(var fs=new FileStream(path,FileMode.Create))
        using(var bw=new BinaryWriter(fs)){
            bw.Write(new byte[]{82,73,70,70}); bw.Write(36+ds); bw.Write(new byte[]{87,65,86,69});
            bw.Write(new byte[]{102,109,116,32}); bw.Write(16);
            bw.Write((short)1); bw.Write((short)1); bw.Write(SR); bw.Write(SR*2);
            bw.Write((short)2); bw.Write((short)16);
            bw.Write(new byte[]{100,97,116,97}); bw.Write(ds);
            foreach(var v in samples){double c=v<-1?-1:v>1?1:v; bw.Write((short)Math.Round(c*32767));}
        }
        int ms=(int)Math.Round(samples.Length*1000.0/SR);
        Console.WriteLine("  OK  " + Path.GetFileName(path) + "  (" + ms + "ms)");
    }
}
'@

$out = 'd:\Github\ta\assets\audio\sfx'

# S-07: sfx_profit_small — 동전 딸랑 (기본음 1200Hz + 배음 2400/3600Hz 지수감쇠)
$buf7 = New-Object double[] ([int](0.30 * [WavGen2]::SR))
[WavGen2]::MixInto($buf7, [WavGen2]::ExpDecay(1200, 0.28, 18, 0.55), 0)
[WavGen2]::MixInto($buf7, [WavGen2]::ExpDecay(2400, 0.15, 25, 0.20), 0)
[WavGen2]::MixInto($buf7, [WavGen2]::ExpDecay(3600, 0.10, 35, 0.10), 0)
[WavGen2]::Norm($buf7, 0.80)
[WavGen2]::Save("$out\sfx_profit_small.wav", $buf7)

# S-12: sfx_level_up — C5-E5-G5 상승 아르페지오 (레벨업 특유의 밝은 높은 음)
$l1  = [WavGen2]::Tone(523.25, 0.11, 0.55, 0.004, 0.025)
$l2  = [WavGen2]::Tone(659.25, 0.11, 0.55, 0.004, 0.025)
$l3  = [WavGen2]::Tone(783.99, 0.20, 0.55, 0.004, 0.070)
$s12 = [WavGen2]::Cat(@($l1, $l2, $l3))
[WavGen2]::Norm($s12, 0.82)
[WavGen2]::Save("$out\sfx_level_up.wav", $s12)

Write-Host ""
Write-Host "완료."
