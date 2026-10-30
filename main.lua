require "import"
import "android.app.AlertDialog"
import "android.widget.*"
import "android.content.*"
import "android.content.DialogInterface"
import "android.graphics.Color"
import "android.view.*"
import "org.json.JSONObject"
import "org.json.JSONArray"
import "java.io.File"
import "android.speech.tts.TextToSpeech"
import "java.util.Locale"
import "android.os.*"
import "java.lang.Runnable"
import "android.media.*"
import "android.provider.Settings"
import "android.net.Uri"
import "java.net.URLEncoder"


-- ===================== ADAPTASI ANDLUA+ =====================
-- Konteks bertema terang untuk semua dialog & view (pengganti "service" milik Jieshuo)
local ctxApp = ContextThemeWrapper(activity, android.R.style.Theme_DeviceDefault_Light_Dialog_Alert)

-- Pengganti task(ms, fungsi) milik Jieshuo
local _handlerTunda = Handler(Looper.getMainLooper())
function tugasTunda(ms, fn)
    pcall(function()
        _handlerTunda.postDelayed(Runnable{run = function() pcall(fn) end}, math.floor(ms))
    end)
end

-- Pengganti service.speak() (suara cadangan bila Google TTS gagal)
function bicaraCadangan(teks)
    pcall(function()
        if not _G.TTSCadangan then
            _G.TTSCadanganSiap = false
            _G.TTSCadangan = TextToSpeech(ctxApp, TextToSpeech.OnInitListener{onInit = function(st)
                if st == TextToSpeech.SUCCESS then pcall(function() _G.TTSCadangan.setLanguage(Locale("id", "ID")) end); _G.TTSCadanganSiap = true end
            end})
        end
        local function ucap() _G.TTSCadangan.speak(teks, 1, nil) end
        if _G.TTSCadanganSiap then ucap() else tugasTunda(1000, function() pcall(ucap) end) end
    end)
end

function sembunyikanApp() pcall(function() activity.moveTaskToBack(true) end) end
function keluarTotal()
    pcall(function() hentikanAudioDanSimpan() end)
    pcall(function() _G.SesiMesinAktif = (_G.SesiMesinAktif or 1) + 1 end)
    pcall(function() if _G.MesinWakeLock and _G.MesinWakeLock.isHeld() then _G.MesinWakeLock.release() end end)
    pcall(function() matikanPenjagaSunyi() end)
    pcall(function() activity.finish() end)
end

-- Tombol Back: sembunyikan app, bukan menutup (supaya jadwal tetap jalan)
function onKeyDown(kode, event)
    if kode == 4 then sembunyikanApp(); return true end
end
-- ============================================================

math.randomseed(os.time())
local JString = luajava.bindClass("java.lang.String")
function jalankanDiUI(fungsi) pcall(function() Handler(Looper.getMainLooper()).post(Runnable{run=function() pcall(fungsi) end}) end) end
function lapor(t) pcall(function() if _G.tvMuat then _G.tvMuat.setText("Jadwal Salat by Reno\n"..t) end end) end
function tampilkanGalatLayar(pesan)
    pcall(function()
        local tv = TextView(activity); tv.setText("GALAT MENU:\n\n"..tostring(pesan)); tv.setTextSize(14)
        tv.setTextColor(Color.BLACK); tv.setPadding(30,120,30,30); tv.setTextIsSelectable(true)
        local sv = ScrollView(activity); sv.addView(tv); activity.setContentView(sv)
    end)
end
function jalankanDiUILapor(fungsi)
    pcall(function() Handler(Looper.getMainLooper()).post(Runnable{run=function()
        local ok, e = pcall(fungsi); if not ok then tampilkanGalatLayar(e) end
    end}) end)
end

local tampilkanMenuUtama, menuFiturLanjutan, menuTesAudio, menuPengaturanAudioMedia, menuPengaturanDurasi, menuJadwalBulanan, menuDiagnostik, bukaMenuPanduan, bukaMenuTentang, menuSakelarSunnah, bukaMenuPilihSuaraTTS, menuPengaturanLokasi, menuProfilLokasi, menuKalenderHijriyah, menuKalenderJawa, menuVolumeCerdas, menuPengaturanAdzan, menuAlarmPribadi, menuRadarKiblat, menuSelisihManual

local pm = ctxApp.getSystemService(Context.POWER_SERVICE)
local PowerManager = luajava.bindClass("android.os.PowerManager")
local LinearLayoutParams = luajava.bindClass("android.widget.LinearLayout$LayoutParams")

-- Perapi tampilan: kasih jarak antar elemen biar ga nempel/berantakan
function rapikanJarak(view, atas, bawah)
    pcall(function()
        local lp = LinearLayoutParams(LinearLayoutParams.MATCH_PARENT, LinearLayoutParams.WRAP_CONTENT)
        lp.setMargins(0, atas or 8, 0, bawah or 8)
        view.setLayoutParams(lp)
    end)
end

function styleTombol(b, bg, tc, atas, bawah, indukLayout, kiri, kanan)
    b.setPadding(30, 26, 30, 26)
    b.setGravity(Gravity.LEFT)
    b.setAllCaps(false)
    if bg then b.setBackgroundColor(Color.parseColor(bg)) end
    if tc then b.setTextColor(Color.parseColor(tc)) end
    pcall(function()
        -- lebar ikut orientasi induk: penuh (vertikal) atau sesuai isi (horizontal), sama seperti perilaku bawaan Android sebelumnya
        local lebar = LinearLayoutParams.MATCH_PARENT
        if indukLayout then
            local ok, orientasi = pcall(function() return indukLayout.getOrientation() end)
            if ok and orientasi == 0 then lebar = LinearLayoutParams.WRAP_CONTENT end
        end
        local lp = LinearLayoutParams(lebar, LinearLayoutParams.WRAP_CONTENT)
        lp.setMargins(kiri or 0, atas or 8, kanan or 0, bawah or 8)
        b.setLayoutParams(lp)
    end)
end
pcall(function() _G.AudioWakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "JadwalSalat:SiaranAktif") end)
pcall(function() _G.IqomahWakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "JadwalSalat:TungguIqomah") end)
pcall(function() _G.MesinWakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "JadwalSalat:Mesin"); _G.MesinWakeLock.setReferenceCounted(false) end)
-- selama MASTER aktif, CPU dijaga tetap hidup supaya jadwal tetap berjalan saat app di latar belakang
function jagaMesinTetapHidup()
    pcall(function()
        if not _G.MesinWakeLock then return end
        if _G.AdzanConfig and _G.AdzanConfig.master_aktif then
            if _G.MesinPanas == true then
                _G.MesinWakeLock.acquire(600000)
            elseif _G.MesinWakeLock.isHeld() then
                _G.MesinWakeLock.release()
            end
        else
            if _G.MesinWakeLock.isHeld() then _G.MesinWakeLock.release() end
            pcall(matikanPenjagaSunyi)
        end
    end)
end

function pegangWakeLock() pcall(function() if _G.AudioWakeLock and not _G.AudioWakeLock.isHeld() then _G.AudioWakeLock.acquire(300000) end end) end
function lepasWakeLock() pcall(function() if _G.AudioWakeLock and _G.AudioWakeLock.isHeld() then _G.AudioWakeLock.release() end end) end

local pathPlugin = ""
do
    local envPath = Environment.getExternalStorageDirectory().getAbsolutePath()
    -- folder lama (kalau ada) tetap dipakai supaya config & murottal lama ikut terbaca
    local kandidat = {envPath .. "/jieshuo/Plugin/nidaul masjid pro/", envPath .. "/解说/Plugin/nidaul masjid pro/", envPath .. "/Nidaul Masjid Pro/", envPath .. "/Jadwal Salat by Reno/"}
    for _, p in ipairs(kandidat) do
        if File(p).exists() then pathPlugin = p; break end
    end
    if pathPlugin == "" then
        -- HP baru: pakai folder khusus app (tanpa izin, jalan di semua HP)
        pcall(function() pathPlugin = activity.getExternalFilesDir(nil).getAbsolutePath() .. "/" end)
    end
    if pathPlugin == "" then
        pcall(function() pathPlugin = activity.getFilesDir().getAbsolutePath() .. "/" end)
    end
end
if not pathPlugin:match("/$") then pathPlugin = pathPlugin .. "/" end

-- ===================== PENJAGA SAAT LAYAR MATI =====================
-- Memutar audio hening berulang supaya Android menganggap app sedang aktif memutar suara,
-- sehingga proses & timer jadwal salat tidak dibekukan ketika layar mati / app disembunyikan.
local function le32(v) return string.char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256) end
local function le16(v) return string.char(v % 256, math.floor(v / 256) % 256) end

function buatFileHening(path)
    local n = 16000 -- 2 detik, 8000 Hz, mono, 8 bit
    local f = io.open(path, "wb")
    if not f then return false end
    f:write("RIFF", le32(36 + n), "WAVE", "fmt ", le32(16), le16(1), le16(1), le32(8000), le32(8000), le16(1), le16(8), "data", le32(n))
    f:write(string.rep(string.char(128), n))
    f:close()
    return true
end

function nyalakanPenjagaSunyi()
    pcall(function()
        if _G.mpSunyi then
            local ok, main = pcall(function() return _G.mpSunyi.isPlaying() end)
            if ok and main then return end
            pcall(function() _G.mpSunyi.release() end); _G.mpSunyi = nil
        end
        local path = pathPlugin .. "hening.wav"
        if not File(path).exists() or File(path).length() < 100 then
            if not buatFileHening(path) then return end
        end
        local mp = MediaPlayer()
        mp.setDataSource(path)
        pcall(function()
            local AA = luajava.bindClass("android.media.AudioAttributes")
            local b = luajava.newInstance("android.media.AudioAttributes$Builder")
            b.setUsage(AA.USAGE_MEDIA); b.setContentType(AA.CONTENT_TYPE_MUSIC)
            mp.setAudioAttributes(b.build())
        end)
        pcall(function() mp.setWakeMode(ctxApp, PowerManager.PARTIAL_WAKE_LOCK) end)
        mp.setLooping(true)
        mp.prepare(); mp.start()
        _G.mpSunyi = mp
    end)
end

function matikanPenjagaSunyi()
    pcall(function()
        if _G.mpSunyi then
            pcall(function() _G.mpSunyi.stop() end); pcall(function() _G.mpSunyi.release() end)
            _G.mpSunyi = nil
        end
    end)
end
-- ===================================================================

local pathMurottal = pathPlugin .. "murottal/"
local configFile = pathPlugin .. "config.json"
local gembokFile = pathPlugin .. "gembok_status.json"

function inisialisasiKonfigurasi()
    _G.AdzanConfig = _G.AdzanConfig or {}
    local cfg = _G.AdzanConfig
    cfg.kota = cfg.kota or "Belum Diatur"; cfg.idKota = cfg.idKota or ""; cfg.lokasiDitemukan = cfg.lokasiDitemukan or ""
    cfg.jenisSuaraTTS = cfg.jenisSuaraTTS or "default"; cfg.ttsSpeed = cfg.ttsSpeed or 1.0; cfg.ttsPitch = cfg.ttsPitch or 1.0
    cfg.master_aktif = cfg.master_aktif == nil and true or cfg.master_aktif
    cfg.lokasiOtomatis = cfg.lokasiOtomatis == nil and true or cfg.lokasiOtomatis
    cfg.lokasiCekTerakhir = cfg.lokasiCekTerakhir or 0
    cfg.memMurottal = cfg.memMurottal or {}; cfg.memMurottalOn = cfg.memMurottalOn or {}
    
    cfg.adzan_subuh_on = cfg.adzan_subuh_on == nil and true or cfg.adzan_subuh_on
    cfg.adzan_dzuhur_on = cfg.adzan_dzuhur_on == nil and true or cfg.adzan_dzuhur_on
    cfg.adzan_ashar_on = cfg.adzan_ashar_on == nil and true or cfg.adzan_ashar_on
    cfg.adzan_maghrib_on = cfg.adzan_maghrib_on == nil and true or cfg.adzan_maghrib_on
    cfg.adzan_isya_on = cfg.adzan_isya_on == nil and true or cfg.adzan_isya_on
    
    cfg.tarhim_subuh_on = cfg.tarhim_subuh_on == nil and true or cfg.tarhim_subuh_on
    cfg.tarhim_dzuhur_on = cfg.tarhim_dzuhur_on == nil and true or cfg.tarhim_dzuhur_on
    cfg.tarhim_ashar_on = cfg.tarhim_ashar_on == nil and true or cfg.tarhim_ashar_on
    cfg.tarhim_maghrib_on = cfg.tarhim_maghrib_on == nil and true or cfg.tarhim_maghrib_on
    cfg.tarhim_isya_on = cfg.tarhim_isya_on == nil and true or cfg.tarhim_isya_on

    cfg.s_jam = cfg.s_jam == nil and false or cfg.s_jam; cfg.s_istiwa = cfg.s_istiwa == nil and false or cfg.s_istiwa
    cfg.s_preterbit = cfg.s_preterbit == nil and false or cfg.s_preterbit; cfg.s_terbit = cfg.s_terbit == nil and false or cfg.s_terbit
    cfg.s_dhuha = cfg.s_dhuha == nil and false or cfg.s_dhuha; cfg.s_tahajud = cfg.s_tahajud == nil and false or cfg.s_tahajud
    cfg.s_imsak = cfg.s_imsak == nil and false or cfg.s_imsak; cfg.s_puasa = cfg.s_puasa == nil and false or cfg.s_puasa
    cfg.s_jumat = cfg.s_jumat == nil and false or cfg.s_jumat; cfg.s_rawatib = cfg.s_rawatib == nil and false or cfg.s_rawatib
    cfg.s_khusyuk = cfg.s_khusyuk == nil and false or cfg.s_khusyuk; cfg.s_kehatihatian = cfg.s_kehatihatian == nil and false or cfg.s_kehatihatian
    cfg.s_musafir = cfg.s_musafir == nil and false or cfg.s_musafir
    cfg.modeMurottal = cfg.modeMurottal or "ikatan"; cfg.lastMurottalPath = cfg.lastMurottalPath or ""; cfg.lastMurottalPos = cfg.lastMurottalPos or 0
    cfg.ikhtiar = cfg.ikhtiar or 0; cfg.audioStream = cfg.audioStream or AudioManager.STREAM_MUSIC
    cfg.volAdzan = cfg.volAdzan or 100; cfg.volMurottal = cfg.volMurottal or 60
    cfg.waktuMurottal = cfg.waktuMurottal or 30; cfg.waktuTarhim = cfg.waktuTarhim or 6; cfg.waktuIqomah = cfg.waktuIqomah or 10
    cfg.waktuArham = cfg.waktuArham or 10
    cfg.iqomah_on = cfg.iqomah_on == nil and true or cfg.iqomah_on
    for _, n in ipairs({"subuh","dzuhur","ashar","maghrib","isya"}) do local k = "murottal_"..n.."_on"; if cfg[k] == nil then cfg[k] = true end end
    cfg.durasiKhusyuk = cfg.durasiKhusyuk or 30; 
    cfg.autoVolume = cfg.autoVolume == nil and false or cfg.autoVolume
    cfg.getarAwal = cfg.getarAwal == nil and false or cfg.getarAwal; 
    cfg.ttsVarian = cfg.ttsVarian == nil and false or cfg.ttsVarian
    
    cfg.deteksiOtomatis = cfg.deteksiOtomatis == nil and true or cfg.deteksiOtomatis
    cfg.adzanSubuhFile = cfg.adzanSubuhFile or ""
    cfg.adzanDzuhurFile = cfg.adzanDzuhurFile or ""
    cfg.adzanAsharFile = cfg.adzanAsharFile or ""
    cfg.adzanMaghribFile = cfg.adzanMaghribFile or ""
    cfg.adzanIsyaFile = cfg.adzanIsyaFile or ""
    
    cfg.tarhimSubuhFile = cfg.tarhimSubuhFile or ""
    cfg.tarhimDzuhurFile = cfg.tarhimDzuhurFile or ""
    cfg.tarhimAsharFile = cfg.tarhimAsharFile or ""
    cfg.tarhimMaghribFile = cfg.tarhimMaghribFile or ""
    cfg.tarhimIsyaFile = cfg.tarhimIsyaFile or ""
    
    cfg.alarm_waktu = cfg.alarm_waktu or ""; cfg.alarm_pesan = cfg.alarm_pesan or ""
    cfg.koreksiHijriyah = cfg.koreksiHijriyah or 0
    cfg.selisih = cfg.selisih or {}
    for _, n in ipairs({"Subuh","Dzuhur","Ashar","Maghrib","Isya"}) do cfg.selisih[n] = cfg.selisih[n] or 0 end
    if cfg.jadwalSebulan == nil then cfg.jadwalSebulan = false end
    if cfg.profilLokasi == nil then cfg.profilLokasi = {} end
end
inisialisasiKonfigurasi()
local cfg = _G.AdzanConfig

_G.GembokAbsolut = _G.GembokAbsolut or {}
_G.TanggalSistem = _G.TanggalSistem or os.date("%Y-%m-%d")
_G.StopDialog = nil
_G.TTSFallback = false
_G.DetakJantung = os.time()
_G.BulanHijriyahIni = _G.BulanHijriyahIni or ""
_G.SedangPutarSpesial = false
_G.VolTerakhirDiputar = 100

_G.SesiMesinAktif = _G.SesiMesinAktif or 1

function pastikanFolder() pcall(function() File(pathPlugin).mkdirs(); File(pathMurottal).mkdirs() end) end
pastikanFolder()

-- Salin audio bawaan (folder "audio" di dalam proyek/APK) ke folder murottal.
-- Hanya menyalin file yang belum ada, jadi aman dijalankan tiap app dibuka.
local function salinAudioBawaan()
    pcall(function()
        local function salinStream(inp, tujuan)
            local out = luajava.newInstance("java.io.FileOutputStream", tujuan)
            luajava.bindClass("android.os.FileUtils").copy(inp, out)
            out.close(); inp.close()
        end
        local namaOk = function(n) n = n:lower(); return n:match("%.mp3$") or n:match("%.ogg$") or n:match("%.m4a$") or n:match("%.wav$") end
        -- 1) dari folder proyek (AndLua+ mengekstrak isi APK ke luaDir)
        local src = File(activity.getLuaDir() .. "/audio")
        if src.exists() and src.isDirectory() then
            local ls = luajava.astable(src.listFiles())
            for _, f in ipairs(ls) do
                local tujuan = File(pathMurottal .. f.getName())
                if f.isFile() and namaOk(f.getName()) and not tujuan.exists() then
                    pcall(function() salinStream(luajava.newInstance("java.io.FileInputStream", f), tujuan) end)
                end
            end
        else
            -- 2) cadangan: dari assets APK
            local daftar = activity.getAssets().list("audio")
            if daftar then
                for i = 0, daftar.length - 1 do
                    local nama = daftar[i]
                    local tujuan = File(pathMurottal .. nama)
                    if namaOk(nama) and not tujuan.exists() then
                        pcall(function() salinStream(activity.getAssets().open("audio/" .. nama), tujuan) end)
                    end
                end
            end
        end
    end)
end
salinAudioBawaan()

function simpanData()
    pcall(function()
        local j = JSONObject()
        j.put("kota", cfg.kota); j.put("idKota", cfg.idKota); j.put("lokasiDitemukan", cfg.lokasiDitemukan)
        j.put("jenisSuaraTTS", cfg.jenisSuaraTTS); j.put("ttsSpeed", cfg.ttsSpeed); j.put("ttsPitch", cfg.ttsPitch)
        j.put("master_aktif", cfg.master_aktif)
        j.put("lokasiOtomatis", cfg.lokasiOtomatis)
        j.put("lokasiCekTerakhir", math.floor(tonumber(cfg.lokasiCekTerakhir) or 0))
        local mmJ = JSONObject()
        for _, n in ipairs({"Subuh", "Dzuhur", "Ashar", "Maghrib", "Isya"}) do
            local it = JSONObject(); local m = cfg.memMurottal[n] or {}
            it.put("path", m.path or ""); it.put("pos", math.floor(m.pos or 0)); it.put("on", cfg.memMurottalOn[n] ~= false)
            mmJ.put(n, it)
        end
        j.put("memMurottal", mmJ)
        
        j.put("adzan_subuh_on", cfg.adzan_subuh_on); j.put("adzan_dzuhur_on", cfg.adzan_dzuhur_on)
        j.put("adzan_ashar_on", cfg.adzan_ashar_on); j.put("adzan_maghrib_on", cfg.adzan_maghrib_on); j.put("adzan_isya_on", cfg.adzan_isya_on)
        j.put("tarhim_subuh_on", cfg.tarhim_subuh_on); j.put("tarhim_dzuhur_on", cfg.tarhim_dzuhur_on)
        j.put("tarhim_ashar_on", cfg.tarhim_ashar_on); j.put("tarhim_maghrib_on", cfg.tarhim_maghrib_on); j.put("tarhim_isya_on", cfg.tarhim_isya_on)

        j.put("s_jam", cfg.s_jam); j.put("s_istiwa", cfg.s_istiwa); j.put("s_preterbit", cfg.s_preterbit)
        j.put("s_terbit", cfg.s_terbit); j.put("s_dhuha", cfg.s_dhuha); j.put("s_tahajud", cfg.s_tahajud)
        j.put("s_imsak", cfg.s_imsak); j.put("s_puasa", cfg.s_puasa); j.put("s_jumat", cfg.s_jumat)
        j.put("s_rawatib", cfg.s_rawatib); j.put("s_khusyuk", cfg.s_khusyuk); j.put("s_kehatihatian", cfg.s_kehatihatian)
        j.put("s_musafir", cfg.s_musafir)
        j.put("modeMurottal", cfg.modeMurottal); j.put("lastMurottalPath", cfg.lastMurottalPath)
        j.put("lastMurottalPos", cfg.lastMurottalPos); j.put("ikhtiar", cfg.ikhtiar)
        j.put("audioStream", cfg.audioStream); j.put("volAdzan", cfg.volAdzan); j.put("volMurottal", cfg.volMurottal)
        j.put("waktuMurottal", cfg.waktuMurottal); j.put("waktuTarhim", cfg.waktuTarhim); j.put("waktuIqomah", cfg.waktuIqomah)
        j.put("waktuArham", cfg.waktuArham); j.put("iqomah_on", cfg.iqomah_on); for _, n in ipairs({"subuh","dzuhur","ashar","maghrib","isya"}) do j.put("murottal_"..n.."_on", cfg["murottal_"..n.."_on"]) end
        j.put("durasiKhusyuk", cfg.durasiKhusyuk); j.put("autoVolume", cfg.autoVolume)
        j.put("getarAwal", cfg.getarAwal); j.put("ttsVarian", cfg.ttsVarian)
        j.put("deteksiOtomatis", cfg.deteksiOtomatis)
        
        j.put("adzanSubuhFile", cfg.adzanSubuhFile); j.put("adzanDzuhurFile", cfg.adzanDzuhurFile)
        j.put("adzanAsharFile", cfg.adzanAsharFile); j.put("adzanMaghribFile", cfg.adzanMaghribFile)
        j.put("adzanIsyaFile", cfg.adzanIsyaFile)
        
        j.put("tarhimSubuhFile", cfg.tarhimSubuhFile); j.put("tarhimDzuhurFile", cfg.tarhimDzuhurFile)
        j.put("tarhimAsharFile", cfg.tarhimAsharFile); j.put("tarhimMaghribFile", cfg.tarhimMaghribFile)
        j.put("tarhimIsyaFile", cfg.tarhimIsyaFile)
        
        j.put("alarm_waktu", cfg.alarm_waktu); j.put("alarm_pesan", cfg.alarm_pesan)
        j.put("koreksiHijriyah", cfg.koreksiHijriyah)
        for _, n in ipairs({"Subuh","Dzuhur","Ashar","Maghrib","Isya"}) do j.put("selisih_" .. n:lower(), cfg.selisih[n] or 0) end
        if type(cfg.jadwalSebulan) == "table" then
            local js = JSONObject(); for tgl, jdw in pairs(cfg.jadwalSebulan) do local item = JSONObject(); for k,v in pairs(jdw) do item.put(k, v) end; js.put(tgl, item) end; j.put("jadwalSebulan", js)
        end
        if type(cfg.profilLokasi) == "table" then
            local ps = JSONObject(); for nama, data in pairs(cfg.profilLokasi) do local item = JSONObject(); item.put("kota", data.kota); item.put("idKota", data.idKota); item.put("lokasi", data.lokasi); ps.put(nama, item) end; j.put("profilLokasi", ps)
        end
        local tmpFile = File(configFile .. ".tmp"); local f = io.open(tmpFile.getAbsolutePath(), "w")
        if f then f:write(j.toString()); f:close(); local asli = File(configFile); if asli.exists() then asli.delete() end; tmpFile.renameTo(asli) end
    end)
end

function muatData()
    pcall(function()
        local f = io.open(configFile, "r")
        if f then
            local isi = f:read("*a"); f:close(); local data = JSONObject(isi)
            cfg.kota = data.optString("kota", "Belum Diatur"); cfg.idKota = data.optString("idKota", ""); cfg.lokasiDitemukan = data.optString("lokasiDitemukan", "")
            cfg.jenisSuaraTTS = data.optString("jenisSuaraTTS", "default"); cfg.ttsSpeed = data.optDouble("ttsSpeed", 1.0); cfg.ttsPitch = data.optDouble("ttsPitch", 1.0)
            cfg.master_aktif = data.optBoolean("master_aktif", true)
            cfg.lokasiOtomatis = data.optBoolean("lokasiOtomatis", cfg.kota == "Belum Diatur")
            cfg.lokasiCekTerakhir = data.optLong("lokasiCekTerakhir", 0)
            pcall(function()
                local mmJ = data.optJSONObject("memMurottal")
                if mmJ then
                    for _, n in ipairs({"Subuh", "Dzuhur", "Ashar", "Maghrib", "Isya"}) do
                        local it = mmJ.optJSONObject(n)
                        if it then cfg.memMurottal[n] = {path = it.optString("path", ""), pos = it.optInt("pos", 0)}; cfg.memMurottalOn[n] = it.optBoolean("on", true) end
                    end
                end
            end)
            
            cfg.adzan_subuh_on = data.optBoolean("adzan_subuh_on", true); cfg.adzan_dzuhur_on = data.optBoolean("adzan_dzuhur_on", true)
            cfg.adzan_ashar_on = data.optBoolean("adzan_ashar_on", true); cfg.adzan_maghrib_on = data.optBoolean("adzan_maghrib_on", true); cfg.adzan_isya_on = data.optBoolean("adzan_isya_on", true)
            cfg.tarhim_subuh_on = data.optBoolean("tarhim_subuh_on", true); cfg.tarhim_dzuhur_on = data.optBoolean("tarhim_dzuhur_on", true)
            cfg.tarhim_ashar_on = data.optBoolean("tarhim_ashar_on", true); cfg.tarhim_maghrib_on = data.optBoolean("tarhim_maghrib_on", true); cfg.tarhim_isya_on = data.optBoolean("tarhim_isya_on", true)

            cfg.s_jam = data.optBoolean("s_jam", false); cfg.s_istiwa = data.optBoolean("s_istiwa", false); cfg.s_preterbit = data.optBoolean("s_preterbit", false)
            cfg.s_terbit = data.optBoolean("s_terbit", false); cfg.s_dhuha = data.optBoolean("s_dhuha", false); cfg.s_tahajud = data.optBoolean("s_tahajud", false)
            cfg.s_imsak = data.optBoolean("s_imsak", false); cfg.s_puasa = data.optBoolean("s_puasa", false); cfg.s_jumat = data.optBoolean("s_jumat", false)
            cfg.s_rawatib = data.optBoolean("s_rawatib", false); cfg.s_khusyuk = data.optBoolean("s_khusyuk", false); cfg.s_kehatihatian = data.optBoolean("s_kehatihatian", false)
            cfg.s_musafir = data.optBoolean("s_musafir", false)
            cfg.modeMurottal = data.optString("modeMurottal", "ikatan"); cfg.lastMurottalPath = data.optString("lastMurottalPath", ""); cfg.lastMurottalPos = data.optInt("lastMurottalPos", 0)
            cfg.ikhtiar = data.optInt("ikhtiar", 0); cfg.audioStream = data.optInt("audioStream", AudioManager.STREAM_MUSIC)
            cfg.volAdzan = data.optInt("volAdzan", 100); cfg.volMurottal = data.optInt("volMurottal", 60)
            cfg.waktuMurottal = data.optInt("waktuMurottal", 30); cfg.waktuTarhim = data.optInt("waktuTarhim", 6); cfg.waktuIqomah = data.optInt("waktuIqomah", 10)
            cfg.waktuArham = data.optInt("waktuArham", 10); cfg.iqomah_on = data.optBoolean("iqomah_on", true); for _, n in ipairs({"subuh","dzuhur","ashar","maghrib","isya"}) do cfg["murottal_"..n.."_on"] = data.optBoolean("murottal_"..n.."_on", true) end
            cfg.durasiKhusyuk = data.optInt("durasiKhusyuk", 30); cfg.autoVolume = data.optBoolean("autoVolume", false); cfg.getarAwal = data.optBoolean("getarAwal", false); cfg.ttsVarian = data.optBoolean("ttsVarian", false)
            
            cfg.deteksiOtomatis = data.optBoolean("deteksiOtomatis", true)
            cfg.adzanSubuhFile = data.optString("adzanSubuhFile", ""); cfg.adzanDzuhurFile = data.optString("adzanDzuhurFile", "")
            cfg.adzanAsharFile = data.optString("adzanAsharFile", ""); cfg.adzanMaghribFile = data.optString("adzanMaghribFile", "")
            cfg.adzanIsyaFile = data.optString("adzanIsyaFile", "")
            
            cfg.tarhimSubuhFile = data.optString("tarhimSubuhFile", ""); cfg.tarhimDzuhurFile = data.optString("tarhimDzuhurFile", "")
            cfg.tarhimAsharFile = data.optString("tarhimAsharFile", ""); cfg.tarhimMaghribFile = data.optString("tarhimMaghribFile", "")
            cfg.tarhimIsyaFile = data.optString("tarhimIsyaFile", "")
            
            cfg.alarm_waktu = data.optString("alarm_waktu", ""); cfg.alarm_pesan = data.optString("alarm_pesan", "")
            cfg.koreksiHijriyah = data.optInt("koreksiHijriyah", 0)
            cfg.selisih = cfg.selisih or {}
            for _, n in ipairs({"Subuh","Dzuhur","Ashar","Maghrib","Isya"}) do cfg.selisih[n] = data.optInt("selisih_" .. n:lower(), 0) end
            if data.has("jadwalSebulan") then
                cfg.jadwalSebulan = {}; local js = data.getJSONObject("jadwalSebulan"); local iter = js.keys()
                while iter.hasNext() do local tgl = iter.next(); local jdw = js.getJSONObject(tgl); cfg.jadwalSebulan[tgl] = {Subuh=jdw.optString("Subuh",""), Terbit=jdw.optString("Terbit",""), Dhuha=jdw.optString("Dhuha",""), Dzuhur=jdw.optString("Dzuhur",""), Ashar=jdw.optString("Ashar",""), Maghrib=jdw.optString("Maghrib",""), Isya=jdw.optString("Isya","")} end
            end
            if data.has("profilLokasi") then
                cfg.profilLokasi = {}; local ps = data.getJSONObject("profilLokasi"); local iter = ps.keys()
                while iter.hasNext() do local nama = iter.next(); local item = ps.getJSONObject(nama); cfg.profilLokasi[nama] = {kota=item.optString("kota",""), idKota=item.optString("idKota",""), lokasi=item.optString("lokasi","")} end
            end
        end
    end)
end
if File(configFile).exists() then muatData() else simpanData() end

function simpanGembok() pcall(function() local j = JSONObject(); for k, v in pairs(_G.GembokAbsolut) do j.put(k, tostring(v)) end; local f = io.open(gembokFile, "w"); if f then f:write(j.toString()); f:close() end end) end
function muatGembok() pcall(function() local f = io.open(gembokFile, "r"); if f then local isi = f:read("*a"); f:close(); local j = JSONObject(isi); local iter = j.keys(); while iter.hasNext() do local k = iter.next(); local v = j.getString(k); if v == "true" then _G.GembokAbsolut[k] = true else _G.GembokAbsolut[k] = v end end end end) end
if File(gembokFile).exists() then muatGembok() end

function bukaPengaturanBaterai()
    pcall(function()
        local Build = luajava.bindClass("android.os.Build")
        local Intent = luajava.bindClass("android.content.Intent")
        local Settings = luajava.bindClass("android.provider.Settings")
        local Uri = luajava.bindClass("android.net.Uri")
        if Build.VERSION.SDK_INT >= 23 then
            local pmSys = ctxApp.getSystemService(Context.POWER_SERVICE)
            local pkgName = ctxApp.getPackageName()
            if not pmSys.isIgnoringBatteryOptimizations(pkgName) then
                local intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                intent.setData(Uri.parse("package:" .. pkgName))
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                ctxApp.startActivity(intent)
            end
        else
            local intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            ctxApp.startActivity(intent)
        end
    end)
end

function aturSuaraTTS()
    pcall(function()
        if not _G.NidaulGoogleTTS then return end
        _G.NidaulGoogleTTS.setLanguage(Locale("id", "ID")); local voices = _G.NidaulGoogleTTS.getVoices()
        if voices then
            local sTarget, sDefault = nil, nil; local iter = voices.iterator()
            while iter.hasNext() do
                local v = iter.next(); local name = v.getName()
                if name:lower():find("id%-id") then if sDefault == nil and not name:lower():find("network") then sDefault = v end; if cfg.jenisSuaraTTS ~= "default" and name == cfg.jenisSuaraTTS then sTarget = v; break end end
            end
            if sTarget then _G.NidaulGoogleTTS.setVoice(sTarget) elseif sDefault then _G.NidaulGoogleTTS.setVoice(sDefault) end
        end
    end)
end

_G.ttsInitListener = TextToSpeech.OnInitListener{ onInit = function(status) if status == TextToSpeech.SUCCESS then _G.TTSFallback = false else _G.TTSFallback = true end end }

function bicaraGoogleTTS(teks, senyapVisual, callbackSelesaiTTS)
    jalankanDiUI(function()
        pcall(function()
            if not senyapVisual then Toast.makeText(ctxApp, teks, Toast.LENGTH_LONG).show() end
            pegangWakeLock()
            
            local isDucking = false
            if _G.mpSistem and _G.mpSistem.isPlaying() then isDucking = true; pcall(function() _G.mpSistem.setVolume(0.1, 0.1) end) end
            
            local durasiTTS = math.max(2500, string.len(teks) * 100)
            
            local function selesaiTTS()
                if isDucking and _G.mpSistem and _G.mpSistem.isPlaying() then 
                    local v=(_G.VolTerakhirDiputar or 60)/100; pcall(function() _G.mpSistem.setVolume(v,v) end) 
                end
                lepasWakeLock()
                if callbackSelesaiTTS then pcall(callbackSelesaiTTS) end
            end
            
            if _G.TTSFallback then bicaraCadangan(teks); tugasTunda(durasiTTS, selesaiTTS); return end
            
            if _G.NidaulGoogleTTS and _G.NidaulGoogleTTS.isLanguageAvailable(Locale("id", "ID")) >= 0 then
                pcall(function()
                    aturSuaraTTS(); _G.NidaulGoogleTTS.setSpeechRate(cfg.ttsSpeed); _G.NidaulGoogleTTS.setPitch(cfg.ttsPitch)
                    _G.NidaulGoogleTTS.speak(teks, 1, nil) 
                    tugasTunda(durasiTTS, selesaiTTS)
                end)
            else
                if _G.NidaulGoogleTTS then pcall(function() _G.NidaulGoogleTTS.shutdown() end) end
                _G.NidaulGoogleTTS = TextToSpeech(ctxApp, _G.ttsInitListener, "com.google.android.tts")
                tugasTunda(500, function()
                    pcall(function()
                        if _G.TTSFallback then bicaraCadangan(teks) else
                            aturSuaraTTS(); _G.NidaulGoogleTTS.setSpeechRate(cfg.ttsSpeed); _G.NidaulGoogleTTS.setPitch(cfg.ttsPitch)
                            _G.NidaulGoogleTTS.speak(teks, 1, nil)
                        end
                        tugasTunda(durasiTTS, selesaiTTS)
                    end)
                end)
            end
        end)
    end)
end

function infoVisual(teks)
    jalankanDiUI(function()
        pcall(function()
            local Toast = luajava.bindClass("android.widget.Toast")
            Toast.makeText(ctxApp, teks, Toast.LENGTH_SHORT).show()
        end)
    end)
end

function tampilkanLaporanVisual(judul, isi, menuAsal, isiSuara)
    jalankanDiUI(function()
        local d; local s = ScrollView(ctxApp); local l = LinearLayout(ctxApp); l.setOrientation(1); l.setPadding(40,40,40,40); local navigasiAktif = false
        local function tutup(tujuan) if not navigasiAktif then navigasiAktif = true; pcall(function() d.dismiss() end); if tujuan then tugasTunda(150, tujuan) end end end
        
        local bKembaliAtas = Button(ctxApp); bKembaliAtas.setText("KEMBALI KE MENU SEBELUMNYA"); styleTombol(bKembaliAtas, "#D32F2F", "#FFFFFF", 0, 12); bKembaliAtas.onClick = function() pcall(function() tutup(menuAsal) end) end; l.addView(bKembaliAtas)
        
        local t = TextView(ctxApp); t.setText(isi); t.setTextColor(Color.BLACK); t.setTextSize(15); t.setPadding(0,20,0,20); l.addView(t)
        local bSalin = Button(ctxApp); bSalin.setText("SALIN TEKS"); styleTombol(bSalin, "#2196F3", "#FFFFFF", 0, 6)
        bSalin.onClick = function() pcall(function() local cb = ctxApp.getSystemService(Context.CLIPBOARD_SERVICE); cb.setPrimaryClip(android.content.ClipData.newPlainText(judul, isi)); infoVisual("Teks berhasil disalin.") end) end; l.addView(bSalin)
        
        local bKembaliBawah = Button(ctxApp); bKembaliBawah.setText("KEMBALI KE MENU SEBELUMNYA"); styleTombol(bKembaliBawah, "#D32F2F", "#FFFFFF", 6, 0); bKembaliBawah.onClick = function() pcall(function() tutup(menuAsal) end) end; l.addView(bKembaliBawah)
        
        s.addView(l); d = AlertDialog.Builder(ctxApp).setTitle(judul).setView(s).create()
        d.setOnCancelListener(DialogInterface.OnCancelListener{onCancel = function() tutup(menuAsal) end}); pcall(function() d.show() end)
        bicaraGoogleTTS(isiSuara or isi, true)
    end)
end

function dapatkanTeksVarian(jenis, param)
    if not cfg.ttsVarian then
        if jenis == "Tarhim" then return "Waktu sholat akan segera tiba. Bersiaplah dengan wudhu dan doa."
        elseif jenis == "Iqomah" then return "Waktu jeda iqomah telah usai. Bersiaplah untuk mendirikan sholat."
        elseif jenis == "Imsak" then return "Waktu Imsak telah tiba. Segera selesaikan sahur Anda."
        elseif jenis == "Istiwa" then return "Waktu istiwa telah masuk. Diharamkan mendirikan sholat hingga adzan Dzuhur."
        elseif jenis == "Tahajud" then return "Sepertiga malam terakhir telah tiba. Bangunlah untuk sholat Tahajud."
        elseif jenis == "Jumat" then return "Hari Jumat. Jangan lupa membaca Al-Kahfi dan mandi sunnah."
        elseif jenis == "Kehati" then return "Peringatan kehati-hatian. Waktu sholat " .. (param or "") .. " tersisa lima belas menit lagi." end
        return ""
    end

    local pool = {
        Subuh = {"Waktu Subuh telah tiba. Sholatlah sebelum matahari terbit.", "Subuh berkumandang. Bangunlah dari tidurmu."},
        Dzuhur = {"Waktu Dzuhur telah tiba. Istirahatkan dirimu sejenak untuk menghadap Allah.", "Dzuhur datang. Tinggalkan sejenak urusan dunia."},
        Ashar = {"Waktu Ashar telah tiba. Bersegeralah sebelum matahari menguning.", "Ashar memanggil. Jangan tunda lagi."},
        Maghrib = {"Waktu Maghrib telah tiba. Bagi yang berpuasa, inilah saatnya berbuka.", "Saat matahari tenggelam, saat itulah Maghrib berkumandang."},
        Isya = {"Waktu Isya telah tiba. Akhiri harimu dengan sujud kepada Allah.", "Jangan tidur sebelum Isya. Dirikanlah sholat sebagai benteng."},
        Dhuha = {"Waktu sholat Dhuha telah masuk."},
        Tahajud = {"Sepertiga malam terakhir telah tiba. Bangunlah untuk sholat Tahajud."},
        Imsak = {"Waktu Imsak telah tiba. Segera selesaikan sahur."},
        Istiwa = {"Waktu istiwa telah masuk. Diharamkan mendirikan sholat hingga adzan Dzuhur."},
        Jumat = {"Hari ini adalah Jumat. Bacalah Al-Kahfi, perbanyak shalawat, dan bersegeralah ke masjid."},
        Tarhim = {"Waktu sholat akan segera tiba. Bersiaplah dengan wudhu dan doa.", "Persiapkan diri Anda, panggilan sholat segera bergema."},
        Iqomah = {"Iqomah telah dikumandangkan. Sholat akan segera dimulai.", "Waktu jeda usai, mari luruskan shaf."},
        Kehati = {"Peringatan kehati-hatian. Waktu sholat %s tersisa lima belas menit lagi."}
    }
    
    if not pool[jenis] then return "" end
    local teks = pool[jenis][math.random(#pool[jenis])]
    if jenis == "Kehati" then teks = string.format(teks, param or "") end
    return teks
end

function getAPI(url, callback) Http.get(url, function(code, content) if code == 200 then callback(true, content) else callback(false, "Peladen menolak akses.") end end) end

function isLewatMaghrib()
    local ok, res = pcall(function()
        local jdw = type(cfg.jadwalSebulan) == "table" and cfg.jadwalSebulan[os.date("%Y-%m-%d")] or nil
        if not jdw or not jdw.Maghrib or jdw.Maghrib == "" then return (tonumber(os.date("%H")) > 17 or (tonumber(os.date("%H")) == 17 and tonumber(os.date("%M")) >= 30)) end
        local hm, mm = tambahMenit(jdw.Maghrib, selisihWaktu("Maghrib")):match("(%d%d):(%d%d)")
        return (tonumber(os.date("%H")) * 60 + tonumber(os.date("%M"))) >= (tonumber(hm) * 60 + tonumber(mm))
    end)
    return ok and res or false
end

function tambahMenit(wStr, menit)
    local ok, res = pcall(function()
        if type(wStr) ~= "string" or wStr == "" then return "" end
        menit = tonumber(menit) or 0; local h, m = wStr:match("(%d%d):(%d%d)"); if not h or not m then return "" end
        local t = tonumber(h) * 60 + tonumber(m) + menit; t = t % 1440; if t < 0 then t = t + 1440 end
        return string.format("%02d:%02d", math.floor(t/60), t%60)
    end)
    return ok and res or wStr
end

-- Total selisih (menit) untuk satu waktu salat: selisih umum (ikhtiar) + selisih manual per waktu
function selisihWaktu(nama)
    local sel = 0
    pcall(function() sel = (tonumber(cfg.ikhtiar) or 0) + (tonumber(cfg.selisih and cfg.selisih[nama]) or 0) end)
    return sel
end

function hitungMenitAbsolut(wStr) 
    local ok, h, m = pcall(function() return wStr:match("(%d%d):(%d%d)") end)
    if not ok or not h or not m then return -1 end
    return tonumber(h) * 60 + tonumber(m) 
end

function formatTanggalIndo(tglStr)
    local ok, res = pcall(function()
        if not tglStr then return "" end
        local y, m, d = tglStr:match("(%d%d%d%d)%-(%d%d)%-(%d%d)"); if not y then return tglStr end
        local wkt = os.time({year=tonumber(y), month=tonumber(m), day=tonumber(d)})
        local hari = {"Minggu", "Senin", "Selasa", "Rabu", "Kamis", "Jumat", "Sabtu"}
        local bln = {"Januari", "Februari", "Maret", "April", "Mei", "Juni", "Juli", "Agustus", "September", "Oktober", "November", "Desember"}
        return hari[tonumber(os.date("%w", wkt))+1] .. ", " .. tonumber(d) .. " " .. bln[tonumber(m)] .. " " .. y
    end)
    return ok and res or tglStr
end

function hitungSisaWaktuTeks()
    if type(cfg.jadwalSebulan) ~= "table" then return "Jadwal Belum Diunduh." end
    local jdw = cfg.jadwalSebulan[os.date("%Y-%m-%d")]; if not jdw or not jdw.Subuh or jdw.Subuh == "" then return "Jadwal Kosong." end
    local sh, sm = os.date("%H:%M"):match("(%d%d):(%d%d)"); local tSekarang = tonumber(sh) * 60 + tonumber(sm)
    local dWaktu = {{n="Subuh", w=tambahMenit(jdw.Subuh, selisihWaktu("Subuh"))}, {n="Terbit", w=jdw.Terbit}, {n="Dzuhur", w=tambahMenit(jdw.Dzuhur, selisihWaktu("Dzuhur"))}, {n="Ashar", w=tambahMenit(jdw.Ashar, selisihWaktu("Ashar"))}, {n="Maghrib", w=tambahMenit(jdw.Maghrib, selisihWaktu("Maghrib"))}, {n="Isya", w=tambahMenit(jdw.Isya, selisihWaktu("Isya"))}}
    local tNama, tSelisih = nil, nil
    for _, w in ipairs(dWaktu) do
        local th, tm = w.w:match("(%d%d):(%d%d)")
        if th and tm then local tTarget = tonumber(th) * 60 + tonumber(tm); if tTarget > tSekarang then tNama = w.n; tSelisih = tTarget - tSekarang; break end end
    end
    if not tNama then local th, tm = dWaktu[1].w:match("(%d%d):(%d%d)"); tNama = "Subuh Besok"; tSelisih = (tonumber(th) * 60 + tonumber(tm) + 1440) - tSekarang end
    return formatTanggalIndo(os.date("%Y-%m-%d")) .. ". Menuju " .. tNama .. ": " .. math.floor(tSelisih / 60) .. " Jam " .. (tSelisih % 60) .. " Menit."
end

function hitungPasaranJawa(offsetHari)
    local shiftMaghrib = (offsetHari == 0 and isLewatMaghrib())
    local t = os.time() + (offsetHari * 86400)
    if shiftMaghrib then t = t + 86400 end
    local sHari = math.floor((t + 25200) / 86400)
    local pasaran = {"Wage", "Kliwon", "Legi", "Pahing", "Pon"}
    local hari = {"Minggu", "Senin", "Selasa", "Rabu", "Kamis", "Jumat", "Sabtu"}
    local namaHari = hari[tonumber(os.date("%w", t)) + 1]
    return (shiftMaghrib and "Malam " or "") .. namaHari .. " " .. pasaran[(sHari % 5) + 1]
end

function ambilTanggalHijriyah(offsetHari, callback)
    pcall(function()
        local shiftMaghrib = (offsetHari == 0 and isLewatMaghrib())
        
        local tReal = os.time() + (offsetHari * 86400)
        if shiftMaghrib then tReal = tReal + 86400 end
        local hari = {"Minggu", "Senin", "Selasa", "Rabu", "Kamis", "Jumat", "Sabtu"}
        local namaHari = hari[tonumber(os.date("%w", tReal)) + 1]
        
        local tHijri = tReal + (cfg.koreksiHijriyah * 86400)
        local tglFormatApi = os.date("%d-%m-%Y", tHijri)
        
        getAPI("https://api.aladhan.com/v1/gToH/" .. tglFormatApi, function(sukses, content)
            jalankanDiUI(function()
                if sukses then
                    pcall(function()
                        local d = JSONObject(content)
                        if not d.has("data") then callback(nil, nil, nil); return end
                        local h = d.getJSONObject("data").getJSONObject("hijri")
                        local mEn = h.getJSONObject("month").getString("en"); local nBulan = mEn
                        if mEn == "Muharram" then nBulan = "Muharram" elseif mEn == "Safar" then nBulan = "Safar" elseif mEn == "Rabi' al-awwal" then nBulan = "Rabiul Awal" elseif mEn == "Rabi' al-thani" then nBulan = "Rabiul Akhir" elseif mEn == "Jumada al-awwal" then nBulan = "Jumadil Awal" elseif mEn == "Jumada al-thani" then nBulan = "Jumadil Akhir" elseif mEn == "Rajab" then nBulan = "Rajab" elseif mEn == "Sha'ban" then nBulan = "Syakban" elseif mEn == "Ramadan" then nBulan = "Ramadhan" elseif mEn == "Shawwal" then nBulan = "Syawal" elseif mEn == "Dhu al-Qi'dah" then nBulan = "Zulkaidah" elseif mEn == "Dhu al-Hijjah" then nBulan = "Zulhijah" end
                        
                        callback((shiftMaghrib and "Malam " or "") .. namaHari .. ", " .. h.getString("day") .. " " .. nBulan .. " " .. h.getString("year") .. " Hijriyah", tonumber(h.getString("day")), nBulan)
                    end)
                else callback(nil, nil, nil) end
            end)
        end)
    end)
end

function radarAudioPintar(kataKunci)
    local sukses, hasil = pcall(function()
        local kL = kataKunci:lower():gsub("[%s%-%_]", ""); local daftarFile = {}
        
        local function sapuFolder(path)
            pcall(function()
                local f = File(path); if not f.exists() then return end
                local list = f.listFiles(); if not list then return end
                local ok, arr = pcall(function() return luajava.astable(list) end)
                if ok and arr then 
                    for _, fileObj in ipairs(arr) do 
                        if fileObj.isFile() then 
                            local name = fileObj.getName():lower()
                            if name:match("%.mp3$") or name:match("%.ogg$") or name:match("%.m4a$") or name:match("%.wav$") then 
                                table.insert(daftarFile, fileObj.getAbsolutePath()) 
                            end 
                        end 
                    end
                else 
                    for i = 0, list.length - 1 do 
                        if list[i].isFile() then 
                            local name = list[i].getName():lower()
                            if name:match("%.mp3$") or name:match("%.ogg$") or name:match("%.m4a$") or name:match("%.wav$") then 
                                table.insert(daftarFile, list[i].getAbsolutePath()) 
                            end 
                        end 
                    end 
                end
            end)
        end
        sapuFolder(pathPlugin); sapuFolder(pathMurottal)
        
        local cocok = {}
        
        for _, p in ipairs(daftarFile) do
            local nB = p:match("([^/]+)$"):lower():gsub("[%s%-%_]", "")
            
            local isAdzan = (nB:find("adzan") or nB:find("azan") or nB:find("ajan") or nB:find("adhan") or nB:find("adzn"))
            local isSubuh = (nB:find("subuh") or nB:find("sbh") or nB:find("shubuh"))
            local isBumper = (nB:find("bumper") or nB:find("pembuka") or nB:find("awal"))
            local isIqomah = (nB:find("iqomah") or nB:find("ikomah") or nB:find("qomat"))
            local isTarhim = (nB:find("tarhim") or nB:find("tarhiim") or nB:find("tahrim"))
            local isArham = (nB:find("arham"))
            
            if kL == "adzan" then 
                if isAdzan and not isSubuh then table.insert(cocok, p) end
            elseif kL == "adzansubuh" then 
                if isAdzan and isSubuh then table.insert(cocok, p) end
            elseif kL == "terbit" then 
                if nB:find("terbit", 1, true) and not nB:find("peringatan", 1, true) then table.insert(cocok, p) end
            elseif kL == "peringatanterbit" then 
                if nB:find("peringatan", 1, true) and nB:find("terbit", 1, true) then table.insert(cocok, p) end
            elseif kL == "aljumuah" then 
                if nB:find("aljumuah", 1, true) or nB:find("jumuah", 1, true) or nB:find("jumat", 1, true) then table.insert(cocok, p) end
            elseif kL == "yasin" then 
                if nB:find("yasin", 1, true) or nB:find("yaasiin", 1, true) then table.insert(cocok, p) end
            elseif kL == "sahur" then 
                if nB:find("sahur", 1, true) then table.insert(cocok, p) end
            elseif kL == "bumper" then 
                if isBumper then table.insert(cocok, p) end
            elseif kL == "tarhim" then 
                if isTarhim then table.insert(cocok, p) end
            elseif kL == "arham" then
                if isArham then table.insert(cocok, p) end
            elseif kL == "dhuha" then 
                if nB:find("dhuha", 1, true) or nB:find("duha", 1, true) then table.insert(cocok, p) end
            elseif kL == "tahajud" then 
                if nB:find("tahajud", 1, true) or nB:find("tahajjud", 1, true) then table.insert(cocok, p) end
            elseif kL == "iqomah" then
                if isIqomah then table.insert(cocok, p) end
            elseif kL == "" then 
                if not (isAdzan or isTarhim or isArham or isBumper or nB:find("sahur") or isIqomah or nB:find("peringatan") or nB:find("terbit") or nB:find("dhuha") or nB:find("tahajud")) then 
                    table.insert(cocok, p) 
                end
            elseif kL == "subuh" or kL == "dzuhur" or kL == "ashar" or kL == "maghrib" or kL == "isya" then 
                if nB:find(kL, 1, true) and not isAdzan then table.insert(cocok, p) end
            else 
                if nB:find(kL, 1, true) then table.insert(cocok, p) end 
            end
        end
        
        if #cocok == 0 and (kL == "subuh" or kL == "dzuhur" or kL == "ashar" or kL == "maghrib" or kL == "isya") then 
            for _, p in ipairs(daftarFile) do 
                local nB = p:match("([^/]+)$"):lower():gsub("[%s%-%_]", "")
                local isAdz = (nB:find("adzan") or nB:find("azan") or nB:find("ajan") or nB:find("adhan") or nB:find("adzn"))
                if (nB:find("murottal") or nB:find("ngaji") or nB:find("surat")) and not isAdz then 
                    table.insert(cocok, p) 
                end 
            end 
        end
        
        if #cocok == 0 and kL == "adzansubuh" then 
            for _, p in ipairs(daftarFile) do 
                local nB = p:match("([^/]+)$"):lower():gsub("[%s%-%_]", "")
                local isAdz = (nB:find("adzan") or nB:find("azan") or nB:find("ajan") or nB:find("adhan") or nB:find("adzn"))
                if isAdz then table.insert(cocok, p) end 
            end 
        end
        
        if #cocok > 0 then return cocok[math.random(#cocok)] end
        return nil
    end)
    return sukses and hasil or nil
end

function tampilkanMediaPlayerUI(namaAudio, menuAsal)
    jalankanDiUI(function()
        pcall(function() if _G.StopDialog then _G.StopDialog.dismiss(); _G.StopDialog = nil end end)
        local l = LinearLayout(ctxApp); l.setOrientation(1); l.setPadding(40,40,40,40)
        local t = TextView(ctxApp); t.setText("Sedang Mengudara\n" .. namaAudio:upper()); t.setTextColor(Color.BLACK); t.setTextSize(16); t.setPadding(0, 0, 0, 40); l.addView(t)
        local navigasiAktif = false
        local function tutup(tujuan) if not navigasiAktif then navigasiAktif = true; pcall(function() _G.StopDialog.dismiss() end); if tujuan then tugasTunda(150, tujuan) end end end
        
        local bStop = Button(ctxApp); bStop.setText("HENTIKAN SIARAN"); styleTombol(bStop, "#F44336", "#FFFFFF", 0, 6)
        bStop.onClick = function() hentikanAudioDanSimpan(); tutup(menuAsal) end; l.addView(bStop)
        
        local bBack = Button(ctxApp); bBack.setText("SEMBUNYIKAN KE LATAR"); styleTombol(bBack, "#2196F3", "#FFFFFF", 6, 0)
        bBack.onClick = function() tutup(menuAsal) end; l.addView(bBack)
        
        _G.StopDialog = AlertDialog.Builder(ctxApp).setTitle("JADWAL SALAT BY RENO - PLAYER").setView(l).setCancelable(false).create()
        _G.StopDialog.getWindow().addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED | WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
        _G.StopDialog.setOnCancelListener(DialogInterface.OnCancelListener{onCancel = function() tutup(menuAsal) end})
        pcall(function() _G.StopDialog.show() end)
    end)
end

function bersihkanMediaPlayer() 
    pcall(function() 
        if _G.mpSistem then 
            if _G.mpSistem.isPlaying() then _G.mpSistem.stop() end; 
            _G.mpSistem.reset(); _G.mpSistem.release(); _G.mpSistem = nil 
        end 
    end) 
end

function hentikanAudioDanSimpan()
    pcall(function()
        local am = ctxApp.getSystemService(Context.AUDIO_SERVICE)
        am.abandonAudioFocus(nil)
        if _G.mpSistem and _G.mpSistem.isPlaying() then
            if cfg.modeMurottal == "sambung" and not _G.SedangPutarSpesial then 
                cfg.lastMurottalPos = _G.mpSistem.getCurrentPosition()
                simpanData() 
            end
            local mpLama = _G.mpSistem
            _G.mpSistem = nil 
            local volCurrent = (_G.VolTerakhirDiputar or 60) / 100
            local step = volCurrent / 10 
            local function prosesFade()
                if mpLama and mpLama.isPlaying() and volCurrent > 0.05 then
                    volCurrent = volCurrent - step
                    pcall(function() mpLama.setVolume(volCurrent, volCurrent) end)
                    tugasTunda(150, prosesFade) 
                else
                    pcall(function() mpLama.stop(); mpLama.reset(); mpLama.release() end)
                end
            end
            prosesFade() 
        else
            bersihkanMediaPlayer()
        end
    end)
    lepasWakeLock(); hilangkanTombolStop()
end

function hilangkanTombolStop() jalankanDiUI(function() if _G.StopDialog then pcall(function() _G.StopDialog.dismiss(); _G.StopDialog = nil end) end end) end

_G.AudioCallbackAction = nil
_G.mpCompletionListener = MediaPlayer.OnCompletionListener{ onCompletion = function(mp) pcall(function() if _G.AudioCallbackAction then pcall(_G.AudioCallbackAction) end; hentikanAudioDanSimpan() end) end }
_G.mpErrorListener = MediaPlayer.OnErrorListener{ onError = function() hentikanAudioDanSimpan(); return true end }

function putarAudioFileLangsung(pathTarget, judulUi, jenis, menuAsal, callbackSelesai)
    pcall(function()
        hentikanAudioDanSimpan()
        _G.SedangPutarSpesial = false
        local sType = cfg.audioStream or AudioManager.STREAM_MUSIC
        local volP = (jenis == "adzan") and (cfg.volAdzan or 100) or (cfg.volMurottal or 60)
        _G.VolTerakhirDiputar = volP
        tampilkanMediaPlayerUI(judulUi, menuAsal)
        jalankanDiUI(function()
            pegangWakeLock()
            local am = ctxApp.getSystemService(Context.AUDIO_SERVICE)
            am.requestAudioFocus(nil, sType, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
            bersihkanMediaPlayer(); _G.mpSistem = MediaPlayer()
            _G.AudioCallbackAction = callbackSelesai
            pcall(function()
                _G.mpSistem.setDataSource(pathTarget); _G.mpSistem.setAudioStreamType(sType); _G.mpSistem.setVolume(volP/100, volP/100)
                _G.mpSistem.setOnCompletionListener(_G.mpCompletionListener); _G.mpSistem.setOnErrorListener(_G.mpErrorListener)
                _G.mpSistem.prepare(); _G.mpSistem.start()
            end)
        end)
    end)
end

function putarAudio(jenis, paramWaktu, menuAsal, pathPaksa)
    pcall(function()
        hentikanAudioDanSimpan()
        _G.SedangPutarSpesial = false
        local pathTarget = nil; local posisi = 0; local judulUi = paramWaktu == "" and "Murottal Acak" or paramWaktu; local tKunci = paramWaktu:lower():gsub("[%s%-%_]", "")
        local sType = cfg.audioStream or AudioManager.STREAM_MUSIC
        local volP = (jenis == "adzan") and (cfg.volAdzan or 100) or (cfg.volMurottal or 60)
        _G.VolTerakhirDiputar = volP
        
        if jenis == "adzan" then 
            local pFile = ""
            if paramWaktu == "Subuh" then pFile = cfg.adzanSubuhFile or ""
            elseif paramWaktu == "Dzuhur" then pFile = cfg.adzanDzuhurFile or ""
            elseif paramWaktu == "Ashar" then pFile = cfg.adzanAsharFile or ""
            elseif paramWaktu == "Maghrib" then pFile = cfg.adzanMaghribFile or ""
            elseif paramWaktu == "Isya" then pFile = cfg.adzanIsyaFile or "" end
            
            if pFile ~= "" then
                local f1 = File(pathMurottal .. pFile)
                local f2 = File(pathPlugin .. pFile)
                if f1.exists() then pathTarget = f1.getAbsolutePath() elseif f2.exists() then pathTarget = f2.getAbsolutePath() end
            end
            
            if not pathTarget then 
                if paramWaktu == "Subuh" then tKunci = "adzansubuh" else tKunci = "adzan" end 
            end
            judulUi = "Adzan " .. paramWaktu
        
        elseif jenis == "murottal" then 
            if tKunci == "aljumuah" then 
                judulUi = "Murottal Al-Jumu'ah"; _G.SedangPutarSpesial = true
            elseif tKunci == "subuh" or tKunci == "dzuhur" or tKunci == "ashar" or tKunci == "maghrib" or tKunci == "isya" then 
                local isMalamJumat = (os.date("%w") == "4" and (tKunci == "maghrib" or tKunci == "isya"))
                if isMalamJumat then tKunci = "yasin"; judulUi = "Murottal Yasin"; _G.SedangPutarSpesial = true end 
            end
        end
        
        if not pathTarget then pathTarget = pathPaksa or radarAudioPintar(tKunci) end
        
        if cfg.modeMurottal == "sambung" and jenis == "murottal" and not _G.SedangPutarSpesial and pathTarget then 
            if cfg.lastMurottalPath == pathTarget then posisi = cfg.lastMurottalPos or 0 else cfg.lastMurottalPath = pathTarget; posisi = 0 end 
        end
        if not pathTarget then bicaraGoogleTTS("Berkas audio tidak ditemukan.", true); pcall(function() if menuAsal then tugasTunda(150, menuAsal) end end); return end
        
        tampilkanMediaPlayerUI(judulUi, menuAsal)
        jalankanDiUI(function()
            pegangWakeLock()
            local am = ctxApp.getSystemService(Context.AUDIO_SERVICE)
            am.requestAudioFocus(nil, sType, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
            bersihkanMediaPlayer(); _G.mpSistem = MediaPlayer()
            _G.AudioCallbackAction = function() if jenis == "adzan" and cfg.s_rawatib then bicaraGoogleTTS("Panggilan adzan telah usai. Dirikanlah sholat sunnah rawatib sebelum iqomah dikumandangkan.", true) end end
            pcall(function()
                _G.mpSistem.setDataSource(pathTarget); _G.mpSistem.setAudioStreamType(sType); _G.mpSistem.setVolume(volP/100, volP/100)
                _G.mpSistem.setOnCompletionListener(_G.mpCompletionListener); _G.mpSistem.setOnErrorListener(_G.mpErrorListener)
                _G.mpSistem.prepare(); if posisi > 0 then _G.mpSistem.seekTo(posisi) end; _G.mpSistem.start()
            end)
        end)
    end)
end

function putarAudioDenganCallback(jenis, paramWaktu, callbackSelesai, menuAsal)
    pcall(function()
        hentikanAudioDanSimpan()
        local sType = cfg.audioStream or AudioManager.STREAM_MUSIC
        local volP = (jenis == "adzan") and (cfg.volAdzan or 100) or (cfg.volMurottal or 60)
        _G.VolTerakhirDiputar = volP
        local pathTarget = radarAudioPintar(paramWaktu:lower():gsub("[%s%-%_]", ""))
        if not pathTarget then if callbackSelesai then pcall(callbackSelesai) end; return end
        tampilkanMediaPlayerUI(paramWaktu, menuAsal)
        jalankanDiUI(function()
            pegangWakeLock()
            local am = ctxApp.getSystemService(Context.AUDIO_SERVICE)
            am.requestAudioFocus(nil, sType, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_EXCLUSIVE)
            bersihkanMediaPlayer(); _G.mpSistem = MediaPlayer(); _G.AudioCallbackAction = callbackSelesai
            pcall(function() _G.mpSistem.setDataSource(pathTarget); _G.mpSistem.setAudioStreamType(sType); _G.mpSistem.setVolume(volP/100, volP/100); _G.mpSistem.setOnCompletionListener(_G.mpCompletionListener); _G.mpSistem.setOnErrorListener(_G.mpErrorListener); _G.mpSistem.prepare(); _G.mpSistem.start() end)
        end)
    end)
end

function eksekusiModeKhusyuk(durasiMenit, namaWaktu)
    if not cfg.s_khusyuk then return end
    pcall(function()
        local am = ctxApp.getSystemService(Context.AUDIO_SERVICE)
        _G.RingerModeLama = am.getRingerMode(); am.setRingerMode(AudioManager.RINGER_MODE_VIBRATE)
        bicaraGoogleTTS("Memasuki waktu " .. namaWaktu .. ". Mode khusyuk diaktifkan.", true)
        tugasTunda(durasiMenit * 60000, function() pcall(function() am.setRingerMode(_G.RingerModeLama or AudioManager.RINGER_MODE_NORMAL); _G.RingerModeLama = nil; bicaraGoogleTTS("Mode khusyuk telah berakhir.", true) end) end)
    end)
end

function eksekusiAutoVolume(callbackSetelah)
    if not cfg.autoVolume then if callbackSetelah then callbackSetelah() end; return end
    pcall(function()
        local am = ctxApp.getSystemService(Context.AUDIO_SERVICE)
        _G.VolumeLama = am.getStreamVolume(AudioManager.STREAM_MUSIC)
        local maxVol = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
        local curVol = _G.VolumeLama
        if curVol < math.floor(maxVol * 0.7) then am.setStreamVolume(AudioManager.STREAM_MUSIC, math.floor(maxVol * 0.85), 0) end
        if callbackSetelah then callbackSetelah() end
    end)
end
function kembalikanVolume() if not cfg.autoVolume or not _G.VolumeLama then return end; pcall(function() local am = ctxApp.getSystemService(Context.AUDIO_SERVICE); am.setStreamVolume(AudioManager.STREAM_MUSIC, _G.VolumeLama, 0); _G.VolumeLama = nil end) end

local function sinkronisasiJadwalV3Cerdas(namaKota, cb, isSiluman)
    pcall(function()
        local URLEncoder = luajava.bindClass("java.net.URLEncoder")
        local kClean = namaKota:lower():gsub("^[kK][oO][tT][aA]%s+", ""):gsub("^[kK][aA][bB]%.?%s+", ""):gsub("^[kK][aA][bB][uU][pP][aA][tT][eE][nN]%s+", "")
        local kUrl = URLEncoder.encode(kClean, "UTF-8")
        getAPI("https://api.myquran.com/v2/sholat/kota/cari/" .. kUrl, function(s, res)
            if not s then if cb then cb(false, "Gagal menghubungi peladen.") end; return end
            local ok, d = pcall(function() return JSONObject(res) end)
            if not ok or not d or d.optBoolean("status") ~= true then if cb then cb(false, "Kota tidak ditemukan.") end; return end
            local arr = d.optJSONArray("data"); if not arr or arr.length() == 0 then if cb then cb(false, "Data kosong.") end; return end
            local fObj = arr.getJSONObject(0); local id = fObj.optString("id", ""); local nResmi = fObj.optString("lokasi", "")
            if id == "" then if cb then cb(false, "ID tidak ditemukan.") end; return end
            cfg.idKota = id; cfg.lokasiDitemukan = nResmi; simpanData()
            getAPI("https://api.myquran.com/v2/sholat/jadwal/" .. id .. "/" .. os.date("%Y/%m"), function(s2, res2)
                if not s2 then if cb then cb(false, "Gagal unduh jadwal.") end; return end
                local ok2, d2 = pcall(function() return JSONObject(res2) end)
                if not ok2 or not d2 or d2.optBoolean("status") ~= true then if cb then cb(false, "Format jadwal salah.") end; return end
                local oJ = d2.optJSONObject("data"); if not oJ then if cb then cb(false, "Struktur jadwal salah.") end; return end
                local arrJadwal = oJ.optJSONArray("jadwal"); if not arrJadwal then if cb then cb(false, "Tabel kosong.") end; return end
                cfg.jadwalSebulan = {}
                for i = 0, arrJadwal.length() - 1 do
                    local item = arrJadwal.getJSONObject(i); local tgl = item.optString("date", "")
                    if tgl ~= "" then cfg.jadwalSebulan[tgl] = {Subuh=item.optString("subuh",""), Terbit=item.optString("terbit",""), Dhuha=item.optString("dhuha",""), Dzuhur=item.optString("dzuhur",""), Ashar=item.optString("ashar",""), Maghrib=item.optString("maghrib",""), Isya=item.optString("isya","")} end
                end
                simpanData(); if cb then cb(true, nResmi) end
            end)
        end)
    end)
end

_G.TarhimBerjalan = false
_G.TarhimMulai = 0
_G.CacheTarhim = {}

-- Pilih berkas tarhim sekali per waktu salat per hari, lalu ukur durasi aslinya
function siapkanTarhim(nama, tglIni)
    local kunci = nama .. tglIni
    local c = _G.CacheTarhim[kunci]
    if c ~= nil then return c or nil end
    local fileKhusus = ""
    if nama == "Subuh" then fileKhusus = cfg.tarhimSubuhFile or ""
    elseif nama == "Dzuhur" then fileKhusus = cfg.tarhimDzuhurFile or ""
    elseif nama == "Ashar" then fileKhusus = cfg.tarhimAsharFile or ""
    elseif nama == "Maghrib" then fileKhusus = cfg.tarhimMaghribFile or ""
    elseif nama == "Isya" then fileKhusus = cfg.tarhimIsyaFile or "" end
    local pathKhusus = nil
    if fileKhusus ~= "" then
        local f1 = File(pathMurottal .. fileKhusus); local f2 = File(pathPlugin .. fileKhusus)
        if f1.exists() then pathKhusus = f1.getAbsolutePath() elseif f2.exists() then pathKhusus = f2.getAbsolutePath() end
    end
    local ap = pathKhusus or radarAudioPintar("tarhim")
    if not ap then _G.CacheTarhim[kunci] = false; return nil end
    local teks = dapatkanTeksVarian("Tarhim")
    local durMs = 0
    pcall(function()
        local mp = MediaPlayer(); mp.setDataSource(ap); mp.prepare(); durMs = mp.getDuration(); mp.release()
    end)
    if not durMs or durMs <= 0 then durMs = 6 * 60000 end
    local ttsDetik = math.max(2.5, string.len(teks) * 0.1)
    -- lead = durasi file + fade murottal + TTS pembuka + jeda + cadangan 6 detik
    local lead = math.ceil(durMs / 1000 + 1.7 + ttsDetik + 1.5 + 6)
    local info = {ap = ap, teks = teks, lead = lead, durMs = durMs}
    _G.CacheTarhim[kunci] = info
    return info
end

-- Deteksi otomatis: durasi file asli yang dipakai, bukan menit pilihan. Hanya jam MULAI yang bergeser,
-- adzan tetap tepat waktu. Pilihan 0 / -1 (OTOMATIS atau OFF) tetap bekerja seperti sebelumnya.
function tarhimOto() return cfg.waktuTarhim == 0 or (cfg.deteksiOtomatis and cfg.waktuTarhim > 0) end
function murottalOto() return cfg.waktuMurottal == -1 or (cfg.deteksiOtomatis and cfg.waktuMurottal > 0) end

-- Mode otomatis (waktuTarhim == 0): mulai = waktu salat - lead. Mode manual: menit tetap seperti dulu.
function saatnyaTarhim(wStr, info)
    if tarhimOto() then
        if not info then return false end
        local t = os.date("*t"); local skr = t.hour * 3600 + t.min * 60 + t.sec
        local tm = hitungMenitAbsolut(wStr); if tm == -1 then return false end
        local sisa = (tm * 60 - skr + 86400) % 86400
        return sisa <= info.lead and sisa >= 30
    end
    return isWaktunya(tambahMenit(wStr, -cfg.waktuTarhim))
end

_G.CacheDurasi = {}
function durasiFileMs(path)
    if not path then return 0 end
    local c = _G.CacheDurasi[path]; if c then return c end
    local d = 0
    pcall(function() local mp = MediaPlayer(); mp.setDataSource(path); mp.prepare(); d = mp.getDuration(); mp.release() end)
    if d and d > 0 then _G.CacheDurasi[path] = d end
    return d or 0
end

-- Pilih berkas (bumper/arham) sekali per hari per waktu salat supaya durasinya bisa dihitung
_G.CachePilih = {}
function pilihBerkas(kataKunci, tglIni, nama)
    local kunci = kataKunci .. "|" .. nama .. "|" .. tglIni
    local c = _G.CachePilih[kunci]
    if c ~= nil then return c or nil end
    local ap = radarAudioPintar(kataKunci)
    _G.CachePilih[kunci] = ap or false
    return ap
end

-- Pilih berkas murottal sekali per hari per waktu salat, lalu ukur panjang aslinya
_G.CacheMurottal = {}
function siapkanMurottal(nama, tglIni, isJumatDzuhur)
    local kunci = nama .. tglIni
    local c = _G.CacheMurottal[kunci]
    if c ~= nil then return c or nil end
    local tKunci = nama:lower(); local spesial = false
    if isJumatDzuhur then tKunci = "aljumuah"; spesial = true
    elseif os.date("%w") == "4" and (tKunci == "maghrib" or tKunci == "isya") then tKunci = "yasin"; spesial = true end
    local ap = radarAudioPintar(tKunci)
    if not ap then _G.CacheMurottal[kunci] = false; return nil end
    local info = {ap = ap, durMs = durasiFileMs(ap), spesial = spesial}
    _G.CacheMurottal[kunci] = info
    return info
end

-- Sisa murottal yang akan diputar (mode sambung melanjutkan dari posisi terakhir)
function sisaMurottalMs(info)
    local sisa = info.durMs or 0
    if cfg.modeMurottal == "sambung" and not info.spesial and cfg.lastMurottalPath == info.ap then sisa = sisa - (cfg.lastMurottalPos or 0) end
    return math.max(sisa, 0)
end

function susunTeksAwal(nama)
    local sMusafir = cfg.s_musafir and ". Mode Musafir aktif, Anda berhak sholat jamak dan qashar." or ""
    local sRamadhan = (_G.BulanHijriyahIni == "Ramadhan" and nama == "Isya") and ". Mari bersiap untuk Tarawih dan Witir." or ""
    return "Waktu sholat " .. nama .. " akan segera tiba" .. sMusafir .. sRamadhan
end

-- Urutan: murottal dihentikan halus -> TTS pembuka sampai selesai -> tarhim -> adzan menunggu
function jalankanTarhim(ap, judul, teks)
    _G.TarhimBerjalan = true; _G.TarhimMulai = os.time()
    hentikanAudioDanSimpan()
    tugasTunda(1700, function()
        bicaraGoogleTTS(teks or dapatkanTeksVarian("Tarhim"), true, function()
            tugasTunda(1500, function()
                putarAudioFileLangsung(ap, judul, "sistem", nil, function() _G.TarhimBerjalan = false end)
            end)
        end)
    end)
end

function isWaktunya(targetWaktu)
    local targetM = hitungMenitAbsolut(targetWaktu)
    if targetM == -1 then return false end
    local skrgM = hitungMenitAbsolut(os.date("%H:%M"))
    local selisih = (skrgM - targetM + 1440) % 1440
    return selisih <= 6
end

-- ===================== PENGHEMAT: CEK HANYA SAAT MENDEKATI WAKTU =====================
-- Mengembalikan 0 bila mesin harus mengecek sekarang (sedang/mendekati waktu kejadian),
-- atau jumlah milidetik untuk tidur sampai mendekati kejadian berikutnya (maksimal 2 menit,
-- supaya detak jantung watchdog dan perubahan pengaturan tetap terbaca).
function hitungTundaMesin()
    local MAKS = 240000
    local ok, hasil = pcall(function()
        if not cfg.master_aktif then return MAKS end
        local tNow = os.date("*t"); local skr = tNow.hour * 3600 + tNow.min * 60 + tNow.sec
        local tglIni = os.date("%Y-%m-%d")
        local panas, terdekat, terdekatBerkala = false, 86400, 86400

        local function catat(mulai, durasi)
            local lalu = (skr - mulai) % 86400
            if lalu < durasi then panas = true; return end
            local ke = (mulai - skr) % 86400
            if ke < terdekat then terdekat = ke end
        end
        local function titik(wStr, offsetMenit)
            local w = tambahMenit(wStr, offsetMenit or 0)
            local m = hitungMenitAbsolut(w)
            if m ~= -1 then catat(m * 60 - 20, 300) end
        end

        -- audio/tarhim yang sedang diputar TIDAK perlu dicek rapat: pemutar punya wakelock sendiri
        -- dan kejadian berikutnya sudah dijaga jendelanya masing-masing.
        -- Iqomah yang menunggu (hanya bila iqomah ON): bangun hanya sekitar jam iqomah, bukan terus-menerus
        for k, v in pairs(_G.GembokAbsolut or {}) do
            if type(k) == "string" and k:find("^IQOMAH_") and type(v) == "string" then
                local mi = hitungMenitAbsolut(v)
                if mi ~= -1 then catat(mi * 60 - 20, 150) else panas = true end
            end
        end
        if panas then return 0 end

        -- laporan jam: menit 00 dan 30 (hanya bila laporan jam ON)
        if cfg.s_jam then
            local r = skr % 1800
            if r < 110 or r >= 1780 then return 0 end
            terdekatBerkala = 1780 - r
        end

        -- alarm pribadi
        if cfg.alarm_waktu and cfg.alarm_waktu ~= "" then titik(cfg.alarm_waktu, 0) end

        local jdw = (type(cfg.jadwalSebulan) == "table") and cfg.jadwalSebulan[tglIni] or nil
        if not jdw or not jdw.Subuh or jdw.Subuh == "" then
            -- jadwal hari ini belum ada: mesin mencoba sinkron otomatis, cek tiap menit
            _G.DetikKeJendela = math.min(terdekat, terdekatBerkala)
            if not panas then return math.min(math.min(terdekat, terdekatBerkala) * 1000, 60000) end
        else
            local wA = {Subuh = tambahMenit(jdw.Subuh, selisihWaktu("Subuh")), Terbit = jdw.Terbit, Dzuhur = tambahMenit(jdw.Dzuhur, selisihWaktu("Dzuhur")), Ashar = tambahMenit(jdw.Ashar, selisihWaktu("Ashar")), Maghrib = tambahMenit(jdw.Maghrib, selisihWaktu("Maghrib")), Isya = tambahMenit(jdw.Isya, selisihWaktu("Isya"))}
            local isJumat = (os.date("%w") == "5")
            local ramadhan = (_G.BulanHijriyahIni == "Ramadhan")

            if cfg.s_tahajud then
                local hm, mm = wA.Maghrib:match("(%d%d):(%d%d)"); local hs, ms = wA.Subuh:match("(%d%d):(%d%d)")
                if hm and hs then
                    local tm = tonumber(hm) * 60 + tonumber(mm); local ts = tonumber(hs) * 60 + tonumber(ms); if ts < tm then ts = ts + 1440 end
                    local thj = tm + (2 * (ts - tm) / 3)
                    titik(string.format("%02d:%02d", math.floor(thj / 60) % 24, math.floor(thj % 60)), 0)
                end
            end
            if ramadhan then titik(wA.Subuh, -60) end
            if cfg.s_preterbit then titik(wA.Terbit, -10) end
            if cfg.s_terbit then titik(wA.Terbit, 0) end
            if cfg.s_dhuha then titik(wA.Terbit, 20) end
            if cfg.s_istiwa then titik(wA.Dzuhur, -5) end
            if cfg.s_jumat and isJumat then titik("10:00", 0) end
            if cfg.s_imsak or ramadhan then titik(wA.Subuh, -10) end
            if cfg.s_puasa then titik(wA.Maghrib, 10) end
            if cfg.s_kehatihatian then
                titik(wA.Ashar, -15); titik(wA.Maghrib, -15); titik(wA.Isya, -15); titik(wA.Subuh, -15)
            end

            local daftar = {
                {n="Subuh", w=wA.Subuh, tarOn=cfg.tarhim_subuh_on, adzOn=cfg.adzan_subuh_on}, {n="Dzuhur", w=wA.Dzuhur, tarOn=cfg.tarhim_dzuhur_on, adzOn=cfg.adzan_dzuhur_on},
                {n="Ashar", w=wA.Ashar, tarOn=cfg.tarhim_ashar_on, adzOn=cfg.adzan_ashar_on}, {n="Maghrib", w=wA.Maghrib, tarOn=cfg.tarhim_maghrib_on, adzOn=cfg.adzan_maghrib_on},
                {n="Isya", w=wA.Isya, tarOn=cfg.tarhim_isya_on, adzOn=cfg.adzan_isya_on},
            }
            for _, w in ipairs(daftar) do
                local tm = hitungMenitAbsolut(w.w)
                local isJumatDzuhur = (w.n == "Dzuhur" and cfg.s_jumat and isJumat)
                local murOn = cfg["murottal_" .. w.n:lower() .. "_on"]
                -- hanya fitur yang ON yang dicek; yang OFF dilewati sepenuhnya
                local butuhTar = (w.tarOn or isJumatDzuhur) and true or false
                local butuhMur = (murOn or isJumatDzuhur) and true or false
                if tm ~= -1 and (w.adzOn or butuhTar or butuhMur) then
                    local pre = 30 -- hanya adzan: bangun 30 detik sebelum waktunya
                    pcall(function()
                        local leadT = 6
                        local infoT = nil
                        if butuhTar then infoT = siapkanTarhim(w.n, tglIni) end
                        if infoT then leadT = tarhimOto() and infoT.lead or (math.max(0, cfg.waktuTarhim or 0) * 60) end
                        local menitMur = (cfg.waktuMurottal == 0) and 30 or (cfg.waktuMurottal or 30)
                        if menitMur < 1 then menitMur = 30 end
                        if not butuhMur then
                            if butuhTar then pre = leadT + 60 end -- murottal OFF: jaga tarhim (+adzan)
                        else
                            pre = (menitMur + math.ceil(leadT / 60)) * 60 + 120
                        end
                        if butuhMur and murottalOto() then
                            local ms = 0
                            if cfg["murottal_" .. w.n:lower() .. "_on"] then
                                local infoM = siapkanMurottal(w.n, tglIni, isJumatDzuhur)
                                ms = infoM and sisaMurottalMs(infoM) or 0
                            end
                            if ms > 0 then
                                local ekstra = 0
                                for _, kk in ipairs({"bumper", "arham"}) do
                                    local ap = pilihBerkas(kk, tglIni, w.n)
                                    if ap then ekstra = ekstra + durasiFileMs(ap) / 1000 end
                                end
                                pre = leadT + ekstra + ms / 1000 + 200
                            end
                        end
                    end)
                    -- setelah adzan: iqomah yang menunggu sudah ditangani pemindai kunci IQOMAH_ (baris atas),
                    -- audio yang sedang jalan juga; jadi jendela ini cukup pendek, baik iqomah ON maupun OFF
                    local akhir = w.adzOn and 90 or 30
                    catat(tm * 60 - pre, pre + akhir)
                end
            end
        end

        if panas then return 0 end
        _G.DetikKeJendela = (cfg.s_jam and math.min(terdekat, terdekatBerkala)) or terdekat
        terdekat = math.min(terdekat, terdekatBerkala)
        local tidur = math.floor(terdekat * 1000)
        if tidur < 5000 then return 0 end
        return math.min(tidur, MAKS)
    end)
    if ok and type(hasil) == "number" then return hasil end
    return 0 -- bila ada galat hitung: jalan seperti biasa
end
-- ====================================================================================

-- ===================== ALARM PEMBANGUN (HP boleh tidur total) =====================
-- Saat jauh dari waktu kejadian, HP dibiarkan tidur. AlarmManager membangunkan app
-- sedikit sebelum jendela kejadian berikutnya (sistem keluar dari Doze untuk alarm ini).
function jadwalkanAlarmBangun(detikKe)
    pcall(function()
        if not detikKe or detikKe <= 0 or detikKe >= 86000 then return end
        local am = ctxApp.getSystemService(Context.ALARM_SERVICE)
        local Intent = luajava.bindClass("android.content.Intent")
        local PI = luajava.bindClass("android.app.PendingIntent")
        local i = Intent(activity.getIntent())
        i.addFlags(805437440) -- NEW_TASK + SINGLE_TOP + REORDER_TO_FRONT
        local pi = PI.getActivity(ctxApp, 7311, i, 201326592) -- UPDATE_CURRENT + IMMUTABLE
        local pemicu = os.time() * 1000 + math.floor(detikKe * 1000) - 5000
        local ok = pcall(function()
            local info = luajava.newInstance("android.app.AlarmManager$AlarmClockInfo", pemicu, pi)
            am.setAlarmClock(info, pi)
        end)
        if not ok then
            pcall(function() am.setExactAndAllowWhileIdle(0, pemicu, pi) end)
            pcall(function() am.setAndAllowWhileIdle(0, pemicu, pi) end)
        end
    end)
end
-- ===================================================================================

function mesinWaktuMasjid(idSesi)
    local sesiSaya = idSesi or _G.SesiMesinAktif
    if _G.SesiMesinAktif ~= sesiSaya then return end
    _G.DetakJantung = os.time()
    jagaMesinTetapHidup()
    
    if not cfg.master_aktif then
        tugasTunda(120000, function() mesinWaktuMasjid(sesiSaya) end)
        return
    end
    
    -- jauh dari waktu kejadian: tidur dulu, jangan cek tiap 5 detik
    local tunda = hitungTundaMesin()
    _G.MesinPanas = (tunda == 0)
    jagaMesinTetapHidup()
    if tunda > 0 then
        jadwalkanAlarmBangun(_G.DetikKeJendela)
        tugasTunda(tunda, function() mesinWaktuMasjid(sesiSaya) end)
        return
    end
    
    pcall(function()
        local tglIni = os.date("%Y-%m-%d"); local skrg = os.date("%H:%M")
        if _G.TanggalSistem ~= tglIni then 
            local gembokBersih = {}
            for kunci, nilai in pairs(_G.GembokAbsolut) do
                if type(kunci) == "string" and kunci:find(tglIni) then
                    gembokBersih[kunci] = nilai
                end
            end
            _G.GembokAbsolut = gembokBersih
            _G.TanggalSistem = tglIni
            simpanGembok() 
            ambilTanggalHijriyah(0, function(h, t, bln) _G.BulanHijriyahIni = bln or "" end)
        end
        local jamSkrg = os.date("%H"); local menitSkrgNum = tonumber(os.date("%M"))
        
        if cfg.alarm_waktu and cfg.alarm_waktu ~= "" and isWaktunya(cfg.alarm_waktu) and not _G.GembokAbsolut["ALARM_PRIBADI_"..tglIni] then
            _G.GembokAbsolut["ALARM_PRIBADI_"..tglIni] = true; simpanGembok()
            local pesan = (cfg.alarm_pesan and cfg.alarm_pesan ~= "") and cfg.alarm_pesan or "Alarm pribadi berbunyi."
            putarAudioDenganCallback("sistem", "bumper", function() 
                tugasTunda(1500, function() bicaraGoogleTTS(pesan, true) end)
            end)
        end
        
        if cfg.s_jam and menitSkrgNum >= 0 and menitSkrgNum <= 5 and not _G.GembokAbsolut["JAM_"..tglIni..jamSkrg] then
            _G.GembokAbsolut["JAM_"..tglIni..jamSkrg] = true; simpanGembok()
            local laporan = "Jam " .. jamSkrg .. " tepat. " .. hitungSisaWaktuTeks():gsub("\n", ". ")
            bicaraGoogleTTS(laporan, true)
        end
        
        if type(cfg.jadwalSebulan) == "table" and not cfg.jadwalSebulan[tglIni] and cfg.idKota ~= "" and not _G.GembokAbsolut["AUTOSYNC_"..tglIni..jamSkrg] then
            _G.GembokAbsolut["AUTOSYNC_"..tglIni..jamSkrg] = true; simpanGembok()
            sinkronisasiJadwalV3Cerdas(cfg.kota, function(s) if s then infoVisual("Jadwal diperbarui otomatis.") end end, true)
        end
        
        if type(cfg.jadwalSebulan) ~= "table" then return end
        local jdw = cfg.jadwalSebulan[tglIni]
        if not jdw or not jdw.Subuh or jdw.Subuh == "" then return end
        
        local wAktif = {Subuh = tambahMenit(jdw.Subuh, selisihWaktu("Subuh")), Terbit = jdw.Terbit, Dhuha = jdw.Dhuha, Dzuhur = tambahMenit(jdw.Dzuhur, selisihWaktu("Dzuhur")), Ashar = tambahMenit(jdw.Ashar, selisihWaktu("Ashar")), Maghrib = tambahMenit(jdw.Maghrib, selisihWaktu("Maghrib")), Isya = tambahMenit(jdw.Isya, selisihWaktu("Isya"))}
        local isJumat = (os.date("%w") == "5")
        
        if cfg.s_tahajud then
            local hm, mm = wAktif.Maghrib:match("(%d%d):(%d%d)"); local hs, ms = wAktif.Subuh:match("(%d%d):(%d%d)")
            if hm and hs then
                local tm = tonumber(hm)*60 + tonumber(mm); local ts = tonumber(hs)*60 + tonumber(ms); if ts < tm then ts = ts + 1440 end; local thj = tm + (2 * (ts - tm) / 3)
                if isWaktunya(string.format("%02d:%02d", math.floor(thj/60)%24, math.floor(thj%60))) and not _G.GembokAbsolut["THJ_"..tglIni] then 
                    _G.GembokAbsolut["THJ_"..tglIni] = true; simpanGembok(); 
                    bicaraGoogleTTS(dapatkanTeksVarian("Tahajud"), true, function()
                        tugasTunda(3000, function() putarAudio("sistem", "tahajud") end) 
                    end)
                end
            end
        end
        
        if _G.BulanHijriyahIni == "Ramadhan" then
            if isWaktunya(tambahMenit(wAktif.Subuh, -60)) and not _G.GembokAbsolut["SAHUR_"..tglIni] then
                _G.GembokAbsolut["SAHUR_"..tglIni] = true; simpanGembok()
                bicaraGoogleTTS("Waktu sahur telah tiba. Subuh tersisa enam puluh menit lagi.", true, function()
                    tugasTunda(2000, function() putarAudio("sistem", "sahur") end)
                end)
            end
        end
        
        if cfg.s_preterbit and isWaktunya(tambahMenit(wAktif.Terbit, -10)) and not _G.GembokAbsolut["PRETERBIT_"..tglIni] then 
            _G.GembokAbsolut["PRETERBIT_"..tglIni] = true; simpanGembok(); 
            putarAudio("sistem", "peringatanterbit")
        end
        
        if cfg.s_terbit and isWaktunya(wAktif.Terbit) and not _G.GembokAbsolut["TERBIT_"..tglIni] then 
            _G.GembokAbsolut["TERBIT_"..tglIni] = true; simpanGembok(); 
            putarAudioDenganCallback("sistem", "terbit", function() 
                tugasTunda(1500, function() bicaraGoogleTTS("Matahari telah terbit sempurna, waktu larangan sholat telah usai.", true) end)
            end)
        end
        
        if cfg.s_dhuha and isWaktunya(tambahMenit(wAktif.Terbit, 20)) and not _G.GembokAbsolut["DHUHA_"..tglIni] then 
            _G.GembokAbsolut["DHUHA_"..tglIni] = true; simpanGembok(); 
            putarAudio("sistem", "dhuha")
        end
        
        if cfg.s_istiwa and isWaktunya(tambahMenit(wAktif.Dzuhur, -5)) and not _G.GembokAbsolut["ISTIWA_"..tglIni] then _G.GembokAbsolut["ISTIWA_"..tglIni] = true; simpanGembok(); bicaraGoogleTTS(dapatkanTeksVarian("Istiwa"), true) end
        
        if cfg.s_jumat and isJumat then
            if isWaktunya("10:00") and not _G.GembokAbsolut["SJ_"..tglIni] then _G.GembokAbsolut["SJ_"..tglIni] = true; simpanGembok(); bicaraGoogleTTS(dapatkanTeksVarian("Jumat"), true) end
            local infoJ = siapkanTarhim("Dzuhur", tglIni)
            if infoJ and saatnyaTarhim(wAktif.Dzuhur, infoJ) and not _G.GembokAbsolut["SIAPJ_"..tglIni] then
                _G.GembokAbsolut["SIAPJ_"..tglIni] = true; simpanGembok()
                jalankanTarhim(infoJ.ap, "Tarhim Jumat", infoJ.teks)
            end
        end
        
        if (cfg.s_imsak or _G.BulanHijriyahIni == "Ramadhan") and isWaktunya(tambahMenit(wAktif.Subuh, -10)) and not _G.GembokAbsolut["IMSAK_"..tglIni] then 
            _G.GembokAbsolut["IMSAK_"..tglIni] = true; simpanGembok(); 
            bicaraGoogleTTS(dapatkanTeksVarian("Imsak"), true) 
        end
        
        if cfg.s_puasa and isWaktunya(tambahMenit(wAktif.Maghrib, 10)) and not _G.GembokAbsolut["PUASA_"..tglIni] then
            _G.GembokAbsolut["PUASA_"..tglIni] = true; simpanGembok()
            local bs = os.date("%w", os.time() + 86400)
            ambilTanggalHijriyah(1, function(teksH, tgl, bln)
                if not tgl or not bln then
                    if bs == "1" or bs == "4" then bicaraGoogleTTS("Besok adalah hari " .. (bs=="1" and "Senin" or "Kamis") .. ". Jangan lupa berniat puasa sunnah.", true) end
                    return
                end
                local pPesan = nil
                if bln == "Muharram" and tgl == 9 then pPesan = "Besok adalah tanggal 9 Muharram. Jangan lupa berniat puasa sunnah Tasu'a."
                elseif bln == "Muharram" and tgl == 10 then pPesan = "Besok adalah tanggal 10 Muharram. Jangan lupa berniat puasa sunnah Asyura."
                elseif bln == "Zulhijah" and tgl == 8 then pPesan = "Besok adalah tanggal 8 Zulhijah. Jangan lupa berniat puasa sunnah Tarwiyah."
                elseif bln == "Zulhijah" and tgl == 9 then pPesan = "Besok adalah tanggal 9 Zulhijah. Jangan lupa berniat puasa sunnah Arafah."
                elseif bln == "Syakban" and tgl == 15 then pPesan = "Besok adalah Nisfu Syakban. Anda dianjurkan berpuasa sunnah dan memperbanyak ibadah."
                elseif bln == "Ramadhan" and tgl == 1 then pPesan = "Alhamdulillah, besok adalah hari pertama bulan suci Ramadhan. Jangan lupa berniat puasa wajib."
                elseif bln == "Syawal" and tgl >= 2 and tgl <= 7 then pPesan = "Besok adalah tanggal " .. tgl .. " Syawal. Mari rutinkan puasa sunnah enam hari Syawal."
                elseif (tgl == 13 or tgl == 14 or tgl == 15) and bln ~= "Ramadhan" and not (bln == "Zulhijah" and tgl == 13) then
                    pPesan = "Besok masuk puasa sunnah Ayyamul Bidh tanggal " .. tgl .. " " .. bln .. "."
                elseif bs == "1" or bs == "4" then 
                    pPesan = "Besok adalah hari " .. (bs=="1" and "Senin" or "Kamis") .. ". Jangan lupa berniat puasa sunnah."
                end
                if pPesan then bicaraGoogleTTS(pPesan, true) end
            end)
        end
        
        if cfg.s_kehatihatian then
            local pAkhir = {{c="Dzuhur", n=wAktif.Ashar}, {c="Ashar", n=wAktif.Maghrib}, {c="Maghrib", n=wAktif.Isya}, {c="Isya", n=wAktif.Subuh}}
            for _, wp in ipairs(pAkhir) do if isWaktunya(tambahMenit(wp.n, -15)) and not _G.GembokAbsolut["HATI_"..wp.c..tglIni] then _G.GembokAbsolut["HATI_"..wp.c..tglIni] = true; simpanGembok(); bicaraGoogleTTS(dapatkanTeksVarian("Kehati", wp.c), true) end end
        end
        
        local daftarWaktuSholat = {
            {n="Subuh", w=wAktif.Subuh, adzOn=cfg.adzan_subuh_on, tarOn=cfg.tarhim_subuh_on},
            {n="Dzuhur", w=wAktif.Dzuhur, adzOn=cfg.adzan_dzuhur_on, tarOn=cfg.tarhim_dzuhur_on},
            {n="Ashar", w=wAktif.Ashar, adzOn=cfg.adzan_ashar_on, tarOn=cfg.tarhim_ashar_on},
            {n="Maghrib", w=wAktif.Maghrib, adzOn=cfg.adzan_maghrib_on, tarOn=cfg.tarhim_maghrib_on},
            {n="Isya", w=wAktif.Isya, adzOn=cfg.adzan_isya_on, tarOn=cfg.tarhim_isya_on}
        }
        
        for _, w in ipairs(daftarWaktuSholat) do
            
            local isJumatDzuhur = (w.n == "Dzuhur" and cfg.s_jumat and isJumat)
            local infoT = nil; local leadTarhim = nil
            if w.tarOn or isJumatDzuhur then
                infoT = siapkanTarhim(w.n, tglIni)
                if infoT and tarhimOto() then leadTarhim = infoT.lead end
            end
            if w.tarOn and infoT and not isJumatDzuhur and saatnyaTarhim(w.w, infoT) and not _G.GembokAbsolut["TARHIM_"..w.n..tglIni] then
                _G.GembokAbsolut["TARHIM_"..w.n..tglIni] = true; simpanGembok()
                jalankanTarhim(infoT.ap, "Tarhim " .. w.n, infoT.teks)
            end
            
            local murOn = cfg["murottal_"..w.n:lower().."_on"]
            local teksAwal = (murOn or isJumatDzuhur) and susunTeksAwal(w.n) or ""
            local teksJ = murOn and "Mendekati waktu sholat Jumat. Memutar Murottal Al-Jumu'ah." or "Mendekati waktu sholat Jumat."
            local jedaMur = (cfg.waktuMurottal == 0 or (w.n == "Subuh" and cfg.waktuArham == 0)) and 0 or 3000
            local jedaArham = (cfg.waktuMurottal == 0) and 0 or 1000
            local infoM = nil
            local siapMur = false
            local menitMur = (cfg.waktuMurottal == 0 and 30 or cfg.waktuMurottal)
            local leadT = 6
            if infoT then leadT = tarhimOto() and infoT.lead or (cfg.waktuTarhim * 60) end

            if not (murOn or isJumatDzuhur) then
                siapMur = false -- murottal OFF: tidak dihitung, tidak dicek
            elseif murottalOto() then
                -- MUROTTAL OTOMATIS: mulai = waktu salat - tarhim - pembuka - panjang murottal
                if cfg.waktuMurottal < 1 then menitMur = 30 end
                if murOn then infoM = siapkanMurottal(w.n, tglIni, isJumatDzuhur) end
                local msM = infoM and sisaMurottalMs(infoM) or 0
                if msM > 0 then
                    local pra = 0
                    if isJumatDzuhur then
                        pra = math.max(2.5, string.len(teksJ) * 0.1) + jedaMur / 1000
                    else
                        local pBumper = pilihBerkas("bumper", tglIni, w.n)
                        if pBumper then pra = pra + durasiFileMs(pBumper) / 1000 + 2 end
                        pra = pra + math.max(2.5, string.len(teksAwal) * 0.1) + jedaMur / 1000
                        if w.n == "Subuh" and cfg.waktuArham > 0 then
                            local pArham = pilihBerkas("arham", tglIni, w.n)
                            if pArham then pra = pra + durasiFileMs(pArham) / 1000 + jedaArham / 1000 end
                        end
                    end
                    local totalMur = leadT + pra + msM / 1000 + 10
                    local tNow = os.date("*t"); local skr = tNow.hour * 3600 + tNow.min * 60 + tNow.sec
                    local tm = hitungMenitAbsolut(w.w)
                    if tm ~= -1 then
                        local sisa = (tm * 60 - skr + 86400) % 86400
                        siapMur = (sisa <= totalMur and sisa > leadT + 60)
                    end
                else
                    -- murottal nonaktif / berkas tidak ditemukan: pengumuman tetap 30 menit sebelum tarhim
                    infoM = nil
                    siapMur = isWaktunya(tambahMenit(w.w, -(menitMur + math.ceil(leadT / 60))))
                end
            else
                if infoT and tarhimOto() then menitMur = menitMur + math.ceil(leadT / 60) end
                siapMur = isWaktunya(tambahMenit(w.w, -menitMur))
            end

            if siapMur and not _G.GembokAbsolut["MUR_"..w.n..tglIni] then
                _G.GembokAbsolut["MUR_"..w.n..tglIni] = true; simpanGembok()
                local pathM = infoM and infoM.ap or nil

                local function putarArhamDanMurottal()
                    if not murOn then return end
                    if cfg.waktuArham > 0 and w.n == "Subuh" then
                        local pArham = pilihBerkas("arham", tglIni, w.n)
                        if pArham then
                            putarAudioFileLangsung(pArham, "Arhamarrohimin", "sistem", nil, function()
                                tugasTunda(jedaArham, function() putarAudio("murottal", w.n, nil, pathM) end)
                            end)
                            return
                        end
                    end
                    putarAudio("murottal", w.n, nil, pathM)
                end

                if isJumatDzuhur then
                    if cfg.getarAwal then pcall(function() ctxApp.getSystemService(Context.VIBRATOR_SERVICE).vibrate(300) end) end
                    bicaraGoogleTTS(teksJ, true, function()
                        if murOn then tugasTunda(jedaMur, function() putarAudio("murottal", "aljumuah", nil, pathM) end) end
                    end)
                else
                    if cfg.getarAwal then pcall(function() ctxApp.getSystemService(Context.VIBRATOR_SERVICE).vibrate(300) end) end
                    local ap = pilihBerkas("bumper", tglIni, w.n)
                    if ap then
                        eksekusiAutoVolume(function()
                            putarAudioFileLangsung(ap, "bumper", "sistem", nil, function()
                                tugasTunda(2000, function()
                                    bicaraGoogleTTS(teksAwal, true, function()
                                        tugasTunda(jedaMur, function() putarArhamDanMurottal(); kembalikanVolume() end)
                                    end)
                                end)
                            end)
                        end)
                    else
                        bicaraGoogleTTS(teksAwal, true, function()
                            tugasTunda(jedaMur, function() putarArhamDanMurottal() end)
                        end)
                    end
                end
            end
            
            local tungguTarhim = false
            if _G.TarhimBerjalan and (os.time() - (_G.TarhimMulai or 0)) < 900 then
                local tNow = os.date("*t"); local detikSkrg = tNow.hour * 3600 + tNow.min * 60 + tNow.sec
                local lewatDetik = (detikSkrg - hitungMenitAbsolut(w.w) * 60 + 86400) % 86400
                if lewatDetik < 30 and not cfg.deteksiOtomatis then tungguTarhim = true end -- adzan menunggu tarhim maksimal 30 detik
            end
            if isWaktunya(w.w) and not tungguTarhim and not _G.GembokAbsolut["ADZ_"..w.n..tglIni] then
                _G.GembokAbsolut["ADZ_"..w.n..tglIni] = true; simpanGembok()
                if not (w.n == "Dzuhur" and cfg.s_jumat and isJumat) then
                    if w.adzOn then
                        hentikanAudioDanSimpan(); eksekusiModeKhusyuk(cfg.durasiKhusyuk, w.n)
                        if cfg.iqomah_on then pcall(function() if _G.IqomahWakeLock and not _G.IqomahWakeLock.isHeld() then _G.IqomahWakeLock.acquire((cfg.waktuIqomah + 2) * 60000) end end) end
                        eksekusiAutoVolume(function() 
                            tugasTunda(2500, function() 
                                putarAudio("adzan", w.n)
                                kembalikanVolume() 
                            end)
                        end)
                        if cfg.iqomah_on then _G.GembokAbsolut["IQOMAH_"..w.n..tglIni] = tambahMenit(w.w, cfg.waktuIqomah); simpanGembok() end
                    else
                        infoVisual("Waktu " .. w.n .. " telah masuk. Adzan otomatis dinonaktifkan.")
                    end
                end
            end
            
            local key = "IQOMAH_"..w.n..tglIni
            if _G.GembokAbsolut[key] and type(_G.GembokAbsolut[key]) == "string" then 
                if isWaktunya(_G.GembokAbsolut[key]) then 
                    local audioSedangJalan = false
                    pcall(function() if _G.mpSistem and _G.mpSistem.isPlaying() then audioSedangJalan = true end end)
                    if audioSedangJalan then
                        _G.GembokAbsolut[key] = tambahMenit(_G.GembokAbsolut[key], 1); simpanGembok()
                        pcall(function() if _G.IqomahWakeLock and not _G.IqomahWakeLock.isHeld() then _G.IqomahWakeLock.acquire(120000) end end)
                    else
                        _G.GembokAbsolut[key] = nil; simpanGembok()
                        pcall(function() if _G.IqomahWakeLock and _G.IqomahWakeLock.isHeld() then _G.IqomahWakeLock.release() end end)
                        if w.adzOn and cfg.iqomah_on then
                            bicaraGoogleTTS(dapatkanTeksVarian("Iqomah"), true, function() tugasTunda(3000, function() putarAudio("sistem", "iqomah") end) end) 
                        end
                    end
                end 
            end
        end
    end)
    tugasTunda(5000, function() mesinWaktuMasjid(sesiSaya) end)
end

if not _G.WatchdogAktif then
    _G.WatchdogAktif = true
    function watchdogMesin() 
        pcall(function() 
            if os.time() - _G.DetakJantung > 600 then 
                _G.SesiMesinAktif = _G.SesiMesinAktif + 1
                tugasTunda(1000, function() mesinWaktuMasjid(_G.SesiMesinAktif) end) 
            end 
        end)
        tugasTunda(300000, watchdogMesin) 
    end
    tugasTunda(300000, watchdogMesin)
end

local function btnLocal(layout, txt, aksi, bg, tc)
    local b = Button(ctxApp); b.setText(txt)
    local horizontal = false
    pcall(function() horizontal = (layout.getOrientation() == 0) end)
    if horizontal then styleTombol(b, bg, tc, 0, 0, layout, 4, 4)
    else styleTombol(b, bg, tc, 6, 6, layout) end
    b.onClick = function() pcall(aksi) end; layout.addView(b)
end

local pList = {"Jawa Timur", "Jawa Tengah & DIY", "DKI Jakarta", "Jawa Barat"}
local kData = {
    ["Jawa Timur"] = {"Bangkalan", "Banyuwangi", "Blitar", "Bojonegoro", "Bondowoso", "Gresik", "Jember", "Jombang", "Kediri", "Lamongan", "Lumajang", "Madiun", "Magetan", "Malang", "Mojokerto", "Nganjuk", "Ngawi", "Pacitan", "Pamekasan", "Pasuruan", "Ponorogo", "Probolinggo", "Sampang", "Sidoarjo", "Situbondo", "Sumenep", "Trenggalek", "Tuban", "Tulungagung", "Kota Batu", "Kota Blitar", "Kota Kediri", "Kota Madiun", "Kota Malang", "Kota Mojokerto", "Kota Pasuruan", "Kota Probolinggo", "Kota Surabaya"},
    ["Jawa Tengah & DIY"] = {"Banjarnegara", "Banyumas", "Batang", "Blora", "Boyolali", "Brebes", "Cilacap", "Demak", "Grobogan", "Jepara", "Karanganyar", "Kebumen", "Kendal", "Klaten", "Kudus", "Magelang", "Pati", "Pekalongan", "Pemalang", "Purbalingga", "Purworejo", "Rembang", "Semarang", "Sragen", "Sukoharjo", "Tegal", "Temanggung", "Wonogiri", "Wonosobo", "Kota Magelang", "Kota Pekalongan", "Kota Salatiga", "Kota Semarang", "Kota Surakarta", "Kota Tegal", "Bantul", "Gunungkidul", "Kulon Progo", "Sleman", "Kota Yogyakarta"},
    ["DKI Jakarta"] = {"Jakarta Barat", "Jakarta Pusat", "Jakarta Selatan", "Jakarta Timur", "Jakarta Utara", "Kepulauan Seribu"},
    ["Jawa Barat"] = {"Bandung", "Bandung Barat", "Bekasi", "Bogor", "Ciamis", "Cianjur", "Cirebon", "Garut", "Indramayu", "Karawang", "Kuningan", "Majalengka", "Pangandaran", "Purwakarta", "Subang", "Sukabumi", "Sumedang", "Tasikmalaya", "Kota Bandung", "Kota Banjar", "Kota Bekasi", "Kota Bogor", "Kota Cimahi", "Kota Cirebon", "Kota Depok", "Kota Sukabumi", "Kota Tasikmalaya"}
}
local function jA(t) local a=luajava.newArray(JString,#t); for i,v in ipairs(t) do a[i-1]=JString(v) end return a end

function dapatkanDaftarBerkas(jenisFilter)
    local arrNama = {"[ ACAK / OTOMATIS ]"}
    local arrPath = {""}
    pcall(function()
        local fs = {}
        local function sP(pth, labelTarget)
            local f = File(pth)
            if f.exists() then
                local ls = f.listFiles()
                if ls then 
                    local ok, l = pcall(function() return luajava.astable(ls) end)
                    if not ok then l = ls end
                    for i = 0, (ok and #l or ls.length) - 1 do
                        local v = ok and l[i+1] or ls[i]
                        if v.isFile() then
                            local name = v.getName():lower()
                            if name:match("%.mp3$") or name:match("%.ogg$") or name:match("%.m4a$") or name:match("%.wav$") then
                                local nB = name:gsub("[%s%-%_]", "")
                                local isAdz = (nB:find("adzan") or nB:find("azan") or nB:find("ajan") or nB:find("adhan") or nB:find("adzn"))
                                local isTarhim = (nB:find("tarhim") or nB:find("tarhiim") or nB:find("tahrim"))
                                local isArham = (nB:find("arham"))
                                
                                if jenisFilter == "adzan" and isAdz then
                                    table.insert(fs, {fileObj=v, label=labelTarget})
                                elseif jenisFilter == "tarhim" and isTarhim then
                                    table.insert(fs, {fileObj=v, label=labelTarget})
                                elseif jenisFilter == "arham" and isArham then
                                    table.insert(fs, {fileObj=v, label=labelTarget})
                                end
                            end
                        end
                    end
                end
            end
        end
        
        sP(pathPlugin, "[ UTAMA ]")
        sP(pathMurottal, "[ FOLDER MUROTTAL ]")
        
        for _, item in ipairs(fs) do 
            table.insert(arrNama, item.label .. " " .. item.fileObj.getName())
            table.insert(arrPath, item.fileObj.getName()) 
        end
    end)
    return arrNama, arrPath
end

menuPengaturanAdzan = function()
    local d; local s = ScrollView(ctxApp); local l = LinearLayout(ctxApp); l.setOrientation(1); l.setPadding(40,40,40,40); local navigasiAktif = false
    local function tutup(tujuan) if not navigasiAktif then navigasiAktif = true; pcall(function() d.dismiss() end); if tujuan then tugasTunda(150, tujuan) end end end
    
    btnLocal(l, "KEMBALI KE MENU UTAMA", function() tutup(tampilkanMenuUtama) end, "#D32F2F", "#FFFFFF")
    
    local nAdzan, pAdzan = dapatkanDaftarBerkas("adzan")
    local nTarhim, pTarhim = dapatkanDaftarBerkas("tarhim")
    
    local t1 = TextView(ctxApp); t1.setText("1. JADWAL SIARAN ADZAN (KHUSUS TIAP WAKTU)"); t1.setTextColor(Color.BLUE); t1.setPadding(0,30,0,10); l.addView(t1)
    
    local function buatSpinnerAudio(judul, keyCfg, nArr, pArr)
        local tv = TextView(ctxApp); tv.setText(judul); tv.setTextColor(Color.BLACK); tv.setPadding(0,10,0,10); l.addView(tv)
        local sp = Spinner(ctxApp); sp.setAdapter(ArrayAdapter(ctxApp, android.R.layout.simple_list_item_1, jA(nArr))); sp.setPadding(0,0,0,20); l.addView(sp)
        local pos = 0; for i, p in ipairs(pArr) do if p == cfg[keyCfg] then pos = i - 1; break end end; sp.setSelection(pos)
        return sp
    end
    
    local spASubuh = buatSpinnerAudio("Memori Adzan Subuh (Disunnahkan Tatswib):", "adzanSubuhFile", nAdzan, pAdzan)
    local spADzuhur = buatSpinnerAudio("Memori Adzan Dzuhur:", "adzanDzuhurFile", nAdzan, pAdzan)
    local spAAshar = buatSpinnerAudio("Memori Adzan Ashar:", "adzanAsharFile", nAdzan, pAdzan)
    local spAMaghrib = buatSpinnerAudio("Memori Adzan Maghrib:", "adzanMaghribFile", nAdzan, pAdzan)
    local spAIsya = buatSpinnerAudio("Memori Adzan Isya:", "adzanIsyaFile", nAdzan, pAdzan)

    local function tg(txt, key) btnLocal(l, (cfg[key] and "[ ON ] " or "[ OFF ] ") .. txt, function() cfg[key] = not cfg[key]; simpanData(); tutup(menuPengaturanAdzan) end, (cfg[key] and "#4CAF50" or "#9E9E9E"), "#FFFFFF") end

    local t2 = TextView(ctxApp); t2.setText("2. SAKELAR ADZAN 5 WAKTU"); t2.setTextColor(Color.BLUE); t2.setPadding(0,30,0,10); l.addView(t2)
    tg("Adzan Subuh", "adzan_subuh_on")
    tg("Adzan Dzuhur", "adzan_dzuhur_on")
    tg("Adzan Ashar", "adzan_ashar_on")
    tg("Adzan Maghrib", "adzan_maghrib_on")
    tg("Adzan Isya", "adzan_isya_on")

    local t3 = TextView(ctxApp); t3.setText("3. SAKELAR TARHIM 5 WAKTU"); t3.setTextColor(Color.BLUE); t3.setPadding(0,30,0,10); l.addView(t3)
    tg("Tarhim Subuh", "tarhim_subuh_on")
    tg("Tarhim Dzuhur", "tarhim_dzuhur_on")
    tg("Tarhim Ashar", "tarhim_ashar_on")
    tg("Tarhim Maghrib", "tarhim_maghrib_on")
    tg("Tarhim Isya", "tarhim_isya_on")

    
    local t4 = TextView(ctxApp); t4.setText("4. JADWAL SIARAN TARHIM (KHUSUS TIAP WAKTU)"); t4.setTextColor(Color.BLUE); t4.setPadding(0,30,0,10); l.addView(t4)
    
    local spTSubuh = buatSpinnerAudio("Memori Tarhim Subuh:", "tarhimSubuhFile", nTarhim, pTarhim)
    local spTDzuhur = buatSpinnerAudio("Memori Tarhim Dzuhur:", "tarhimDzuhurFile", nTarhim, pTarhim)
    local spTAshar = buatSpinnerAudio("Memori Tarhim Ashar:", "tarhimAsharFile", nTarhim, pTarhim)
    local spTMaghrib = buatSpinnerAudio("Memori Tarhim Maghrib:", "tarhimMaghribFile", nTarhim, pTarhim)
    local spTIsya = buatSpinnerAudio("Memori Tarhim Isya:", "tarhimIsyaFile", nTarhim, pTarhim)

    btnLocal(l, "SIMPAN SEMUA PENGATURAN ADZAN & TARHIM", function() 
        cfg.adzanSubuhFile = pAdzan[spASubuh.getSelectedItemPosition() + 1] or ""
        cfg.adzanDzuhurFile = pAdzan[spADzuhur.getSelectedItemPosition() + 1] or ""
        cfg.adzanAsharFile = pAdzan[spAAshar.getSelectedItemPosition() + 1] or ""
        cfg.adzanMaghribFile = pAdzan[spAMaghrib.getSelectedItemPosition() + 1] or ""
        cfg.adzanIsyaFile = pAdzan[spAIsya.getSelectedItemPosition() + 1] or ""
        
        cfg.tarhimSubuhFile = pTarhim[spTSubuh.getSelectedItemPosition() + 1] or ""
        cfg.tarhimDzuhurFile = pTarhim[spTDzuhur.getSelectedItemPosition() + 1] or ""
        cfg.tarhimAsharFile = pTarhim[spTAshar.getSelectedItemPosition() + 1] or ""
        cfg.tarhimMaghribFile = pTarhim[spTMaghrib.getSelectedItemPosition() + 1] or ""
        cfg.tarhimIsyaFile = pTarhim[spTIsya.getSelectedItemPosition() + 1] or ""
        
        simpanData(); infoVisual("Seluruh Pilihan Audio Berhasil Disimpan."); tutup(tampilkanMenuUtama) 
    end, "#2196F3", "#FFFFFF")
    
    btnLocal(l, "KEMBALI KE MENU UTAMA", function() tutup(tampilkanMenuUtama) end, "#D32F2F", "#FFFFFF")
    
    s.addView(l); d = AlertDialog.Builder(ctxApp).setTitle("Adzan & Tarhim").setView(s).create()
    d.setOnCancelListener(DialogInterface.OnCancelListener{onCancel = function() tutup(tampilkanMenuUtama) end}); pcall(function() d.show() end)
end

menuPengaturanDurasi = function()
    local d; local s = ScrollView(ctxApp); local l = LinearLayout(ctxApp); l.setOrientation(1); l.setPadding(40,40,40,40); local navigasiAktif = false
    local function tutup(tujuan) if not navigasiAktif then navigasiAktif = true; pcall(function() d.dismiss() end); if tujuan then tugasTunda(150, tujuan) end end end
    
    btnLocal(l, "KEMBALI KE MENU SEBELUMNYA", function() tutup(menuFiturLanjutan) end, "#D32F2F", "#FFFFFF")
    
    btnLocal(l, (cfg.deteksiOtomatis and "[ ON ] " or "[ OFF ] ") .. "Deteksi durasi file tarhim dan murottal otomatis", function() cfg.deteksiOtomatis = not cfg.deteksiOtomatis; simpanData(); tutup(menuPengaturanDurasi) end, (cfg.deteksiOtomatis and "#4CAF50" or "#9E9E9E"), "#FFFFFF")
    local tvOto = TextView(ctxApp); tvOto.setText("Saat ON, lama tarhim dan murottal dibaca dari panjang file aslinya. Hanya jam mulai yang digeser supaya selesai pas sebelum adzan. Adzan tidak pernah ditunda. Pilihan menit di bawah diabaikan untuk tarhim dan murottal."); tvOto.setTextSize(13); tvOto.setPadding(0,10,0,10); l.addView(tvOto)
    local function renderOpsi(judul, keyVar, arrPilihan, teksNol)
        local tv = TextView(ctxApp); tv.setText(judul .. " (" .. (cfg[keyVar] == 0 and (teksNol or "OFF") or (cfg[keyVar] == -1 and "OTOMATIS") or cfg[keyVar] .. " Menit") .. ")"); tv.setTextColor(Color.BLUE); tv.setPadding(0,20,0,10); l.addView(tv)
        local lH = LinearLayout(ctxApp); lH.setOrientation(0); for _, v in ipairs(arrPilihan) do btnLocal(lH, (v==0 and (teksNol or "OFF") or (v==-1 and "OTOMATIS") or tostring(v)), function() cfg[keyVar] = v; simpanData(); tutup(menuPengaturanDurasi) end, (cfg[keyVar] == v) and "#4CAF50" or nil, (cfg[keyVar] == v) and "#FFFFFF" or nil) end
        local hsv = HorizontalScrollView(ctxApp); hsv.addView(lH); l.addView(hsv)
    end
    renderOpsi("Ya Arhamarrohimin (Pra-Murottal)", "waktuArham", {0, 5, 10, 15, 20})
    renderOpsi("Durasi Murottal Pra-Adzan", "waktuMurottal", {-1, 0, 10, 15, 30, 45, 60}); renderOpsi("Durasi Tarhim Harian", "waktuTarhim", {0, 5, 6, 10, 15}, "OTOMATIS")
    renderOpsi("Jeda Iqomah", "waktuIqomah", {5, 10, 15, 20}); renderOpsi("Durasi Mode Khusyuk", "durasiKhusyuk", {20, 30, 40, 60})
    
    btnLocal(l, "KEMBALI KE MENU SEBELUMNYA", function() tutup(menuFiturLanjutan) end, "#D32F2F", "#FFFFFF")
    
    s.addView(l); d = AlertDialog.Builder(ctxApp).setTitle("Durasi Waktu").setView(s).create()
    d.setOnCancelListener(DialogInterface.OnCancelListener{onCancel = function() tutup(menuFiturLanjutan) end}); pcall(function() d.show() end)
end

menuAlarmPribadi = function()
    local d; local s = ScrollView(ctxApp); local l = LinearLayout(ctxApp); l.setOrientation(1); l.setPadding(40,40,40,40); local navigasiAktif = false
    local function tutup(tujuan) if not navigasiAktif then navigasiAktif = true; pcall(function() d.dismiss() end); if tujuan then tugasTunda(150, tujuan) end end end
    
    btnLocal(l, "KEMBALI KE MENU SEBELUMNYA", function() tutup(menuFiturLanjutan) end, "#D32F2F", "#FFFFFF")
    
    local t1 = TextView(ctxApp); t1.setText("Waktu Alarm (Format HH:MM, contoh: 03:15):"); t1.setTextColor(Color.BLUE); t1.setPadding(0,20,0,10); l.addView(t1)
    local eWaktu = EditText(ctxApp); eWaktu.setText(cfg.alarm_waktu or ""); l.addView(eWaktu)
    local t2 = TextView(ctxApp); t2.setText("Pesan Suara (Teks TTS):"); t2.setTextColor(Color.BLUE); t2.setPadding(0,20,0,10); l.addView(t2)
    local ePesan = EditText(ctxApp); ePesan.setText(cfg.alarm_pesan or ""); l.addView(ePesan)
    btnLocal(l, "SIMPAN ALARM", function() 
        local inputWaktu = eWaktu.getText().toString()
        if inputWaktu ~= "" and hitungMenitAbsolut(inputWaktu) == -1 then
            infoVisual("Format waktu salah. Gunakan format HH:MM (contoh: 03:15) dengan angka yang valid.")
            return
        end
        cfg.alarm_waktu = inputWaktu
        cfg.alarm_pesan = ePesan.getText().toString()
        simpanData()
        infoVisual("Alarm pribadi disimpan.")
        tutup(menuFiturLanjutan) 
    end, "#4CAF50", "#FFFFFF")
    btnLocal(l, "HAPUS ALARM", function() cfg.alarm_waktu = ""; cfg.alarm_pesan = ""; simpanData(); infoVisual("Alarm pribadi dinonaktifkan."); tutup(menuFiturLanjutan) end, "#FF9800", "#FFFFFF")
    
    btnLocal(l, "KEMBALI KE MENU SEBELUMNYA", function() tutup(menuFiturLanjutan) end, "#D32F2F", "#FFFFFF")
    
    s.addView(l); d = AlertDialog.Builder(ctxApp).setTitle("Alarm Pribadi").setView(s).create()
    d.setOnCancelListener(DialogInterface.OnCancelListener{onCancel = function() tutup(menuFiturLanjutan) end}); pcall(function() d.show() end)
end

menuRadarKiblat = function()
    local d; local l = LinearLayout(ctxApp); l.setOrientation(1); l.setPadding(40,40,40,40);
    local SensorManager = luajava.bindClass("android.hardware.SensorManager")
    local sm = ctxApp.getSystemService(Context.SENSOR_SERVICE)
    local sensor = sm.getDefaultSensor(3)
    
    local targetKiblat = 294
    local lastSpeak = 0
    local navigasiAktif = false
    local listener = nil
    
    local function tutup(tujuan) 
        if listener then pcall(function() sm.unregisterListener(listener); listener = nil end) end
        if not navigasiAktif then 
            navigasiAktif = true
            pcall(function() d.dismiss() end)
            if tujuan then tugasTunda(150, tujuan) end 
        end 
    end
    
    if sensor then
        btnLocal(l, "HENTIKAN RADAR KOMPAS (KEMBALI)", function() tutup(menuFiturLanjutan) end, "#D32F2F", "#FFFFFF")
        
        listener = luajava.createProxy("android.hardware.SensorEventListener", {
            onSensorChanged = function(event)
                local az = event.values[0]
                local now = os.time()
                if now - lastSpeak >= 2 then
                    local diff = az - targetKiblat
                    if diff > 180 then diff = diff - 360 elseif diff < -180 then diff = diff + 360 end
                    if math.abs(diff) <= 5 then pcall(function() ctxApp.getSystemService(Context.VIBRATOR_SERVICE).vibrate(500) end); bicaraGoogleTTS("Tepat! Anda menghadap Kiblat.", true); lastSpeak = now + 1
                    elseif math.abs(diff) <= 30 then if diff > 0 then bicaraGoogleTTS("Kiri sedikit.", true) else bicaraGoogleTTS("Kanan sedikit.", true) end; lastSpeak = now
                    elseif now - lastSpeak >= 4 then if diff > 0 then bicaraGoogleTTS("Putar ke kiri.", true) else bicaraGoogleTTS("Putar ke kanan.", true) end; lastSpeak = now end
                end
            end,
            onAccuracyChanged = function(sensor, acc) end
        })
        
        btnLocal(l, "HENTIKAN RADAR KOMPAS (KEMBALI)", function() tutup(menuFiturLanjutan) end, "#D32F2F", "#FFFFFF")
        
        d = AlertDialog.Builder(ctxApp).setTitle("Radar Kiblat").setView(l).create()
        d.setOnCancelListener(DialogInterface.OnCancelListener{onCancel = function() tutup(menuFiturLanjutan) end})
        pcall(function() sm.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_UI); d.show(); bicaraGoogleTTS("Radar aktif. Pegang ponsel mendatar dan ikuti petunjuk suara.", true) end)
    else
        btnLocal(l, "KEMBALI KE MENU SEBELUMNYA", function() tutup(menuFiturLanjutan) end, "#D32F2F", "#FFFFFF")
        
        local tInfo = TextView(ctxApp); tInfo.setTextColor(Color.BLACK); tInfo.setTextSize(15)
        tInfo.setText("Sensor kompas fisik tidak ditemukan di perangkat Anda. Mengalihkan ke metode Bayangan Matahari.\n\nPanduan Fiqih: Pada sore hari menjelang Maghrib, pastikan Anda berdiri menghadap ke arah matahari terbenam, lalu serongkan badan Anda sedikit ke arah kanan (sekitar 294 derajat). Itulah arah Kiblat Anda.")
        l.addView(tInfo)
        
        btnLocal(l, "KEMBALI KE MENU SEBELUMNYA", function() tutup(menuFiturLanjutan) end, "#D32F2F", "#FFFFFF")
        
        d = AlertDialog.Builder(ctxApp).setTitle("Radar Kiblat (Astronomi)").setView(l).create()
        d.setOnCancelListener(DialogInterface.OnCancelListener{onCancel = function() tutup(menuFiturLanjutan) end})
        pcall(function() d.show(); bicaraGoogleTTS(tInfo.getText().toString(), true) end)
    end
end

menuKalenderHijriyah = function()
    local d; local l = LinearLayout(ctxApp); l.setOrientation(1); l.setPadding(40,40,40,40); local navigasiAktif = false
    local function tutup(tujuan) if not navigasiAktif then navigasiAktif = true; pcall(function() d.dismiss() end); if tujuan then tugasTunda(150, tujuan) end end end
    
    btnLocal(l, "KEMBALI KE MENU SEBELUMNYA", function() tutup(menuFiturLanjutan) end, "#D32F2F", "#FFFFFF")
    
    local tLengkap = TextView(ctxApp); tLengkap.setGravity(Gravity.CENTER); tLengkap.setTextSize(20); tLengkap.setTextColor(Color.parseColor("#4CAF50")); tLengkap.setPadding(0,30,0,30); l.addView(tLengkap)
    
    local tKoreksi = TextView(ctxApp); tKoreksi.setText("Koreksi Kalender Saat Ini: " .. cfg.koreksiHijriyah .. " Hari"); tKoreksi.setTextColor(Color.BLUE); tKoreksi.setPadding(0,10,0,10); l.addView(tKoreksi)
    local lK = LinearLayout(ctxApp); lK.setOrientation(0)
    
    local off = 0; 
    local function m(o) 
        off = o; tLengkap.setText("Memuat data satelit..."); 
        local tMasehi = formatTanggalIndo(os.date("%Y-%m-%d", os.time() + (o * 86400))); 
        ambilTanggalHijriyah(o, function(h) 
            local teksAkhir = tMasehi .. ".\nBertepatan dengan " .. (h or "Gagal memuat."); 
            tLengkap.setText(teksAkhir); bicaraGoogleTTS(teksAkhir:gsub("\n", " "), true) 
        end) 
    end
    
    btnLocal(lK, "[-] MUNDUR 1 HARI", function() cfg.koreksiHijriyah = cfg.koreksiHijriyah - 1; simpanData(); tKoreksi.setText("Koreksi Kalender Saat Ini: " .. cfg.koreksiHijriyah .. " Hari"); m(off) end, "#FF9800", "#FFFFFF")
    btnLocal(lK, "[+] MAJU 1 HARI", function() cfg.koreksiHijriyah = cfg.koreksiHijriyah + 1; simpanData(); tKoreksi.setText("Koreksi Kalender Saat Ini: " .. cfg.koreksiHijriyah .. " Hari"); m(off) end, "#4CAF50", "#FFFFFF")
    
    local hsv = HorizontalScrollView(ctxApp); hsv.addView(lK); l.addView(hsv)
    
    btnLocal(l, "SALIN TEKS KE PAPAN KLIP", function() pcall(function() local cb = ctxApp.getSystemService(Context.CLIPBOARD_SERVICE); cb.setPrimaryClip(android.content.ClipData.newPlainText("Hijriyah", tLengkap.getText().toString())); infoVisual("Teks disalin.") end) end, "#2196F3", "#FFFFFF")
    
    local lB = LinearLayout(ctxApp); lB.setOrientation(1); rapikanJarak(lB, 10, 10); local bm, bt, bp = Button(ctxApp), Button(ctxApp), Button(ctxApp)
    bm.setText("CEK HARI SEBELUMNYA"); bt.setText("CEK HARI INI"); bp.setText("CEK HARI SELANJUTNYA")
    styleTombol(bp, "#009688", "#FFFFFF", 0, 4); styleTombol(bt, "#607D8B", "#FFFFFF", 4, 4); styleTombol(bm, "#009688", "#FFFFFF", 4, 0)
    lB.addView(bp); lB.addView(bt); lB.addView(bm); l.addView(lB)
    
    bp.onClick = function() m(off+1) end; bt.onClick = function() m(0) end; bm.onClick = function() m(off-1) end
    
    btnLocal(l, "KEMBALI KE MENU SEBELUMNYA", function() tutup(menuFiturLanjutan) end, "#D32F2F", "#FFFFFF")
    
    d = AlertDialog.Builder(ctxApp).setTitle("Kalender Hijriyah").setView(l).create()
    d.setOnCancelListener(DialogInterface.OnCancelListener{onCancel = function() tutup(menuFiturLanjutan) end}); pcall(function() d.show() end); m(0)
end

menuKalenderJawa = function()
    local d; local l = LinearLayout(ctxApp); l.setOrientation(1); l.setPadding(40,40,40,40); local navigasiAktif = false
    local function tutup(tujuan) if not navigasiAktif then navigasiAktif = true; pcall(function() d.dismiss() end); if tujuan then tugasTunda(150, tujuan) end end end
    
    btnLocal(l, "KEMBALI KE MENU SEBELUMNYA", function() tutup(menuFiturLanjutan) end, "#D32F2F", "#FFFFFF")
    
    local tLengkap = TextView(ctxApp); tLengkap.setGravity(Gravity.CENTER); tLengkap.setTextSize(20); tLengkap.setTextColor(Color.parseColor("#4CAF50")); tLengkap.setPadding(0,30,0,30); l.addView(tLengkap)
    btnLocal(l, "SALIN TEKS KE PAPAN KLIP", function() pcall(function() local cb = ctxApp.getSystemService(Context.CLIPBOARD_SERVICE); cb.setPrimaryClip(android.content.ClipData.newPlainText("Jawa", tLengkap.getText().toString())); infoVisual("Teks disalin.") end) end, "#2196F3", "#FFFFFF")
    local lB = LinearLayout(ctxApp); lB.setOrientation(1); rapikanJarak(lB, 10, 10); local bm, bt, bp = Button(ctxApp), Button(ctxApp), Button(ctxApp)
    bm.setText("CEK HARI SEBELUMNYA"); bt.setText("CEK HARI INI"); bp.setText("CEK HARI SELANJUTNYA")
    styleTombol(bp, "#009688", "#FFFFFF", 0, 4); styleTombol(bt, "#607D8B", "#FFFFFF", 4, 4); styleTombol(bm, "#009688", "#FFFFFF", 4, 0)
    lB.addView(bp); lB.addView(bt); lB.addView(bm); l.addView(lB)
    local off = 0; local function m(o) off = o; local tMasehi = formatTanggalIndo(os.date("%Y-%m-%d", os.time() + (o * 86400))); local tJawa = hitungPasaranJawa(o); local teksAkhir = tMasehi .. ".\nBertepatan dengan pasaran " .. tJawa; tLengkap.setText(teksAkhir); bicaraGoogleTTS(teksAkhir:gsub("\n", " "), true) end
    bp.onClick = function() m(off+1) end; bt.onClick = function() m(0) end; bm.onClick = function() m(off-1) end
    
    btnLocal(l, "KEMBALI KE MENU SEBELUMNYA", function() tutup(menuFiturLanjutan) end, "#D32F2F", "#FFFFFF")
    
    d = AlertDialog.Builder(ctxApp).setTitle("Kalender Jawa").setView(l).create()
    d.setOnCancelListener(DialogInterface.OnCancelListener{onCancel = function() tutup(menuFiturLanjutan) end}); pcall(function() d.show() end); m(0)
end

menuJadwalBulanan = function()
    local d; local s = ScrollView(ctxApp); local l = LinearLayout(ctxApp); l.setOrientation(1); l.setPadding(40,40,40,40); local navigasiAktif = false
    local function tutup(tujuan) if not navigasiAktif then navigasiAktif = true; pcall(function() d.dismiss() end); if tujuan then tugasTunda(150, tujuan) end end end
    
    btnLocal(l, "KEMBALI KE MENU SEBELUMNYA", function() tutup(menuFiturLanjutan) end, "#D32F2F", "#FFFFFF")
    
    local tJudul = TextView(ctxApp); tJudul.setTextSize(16); tJudul.setTextColor(Color.BLUE); tJudul.setPadding(0,20,0,20); l.addView(tJudul)
    local tIsi = TextView(ctxApp); tIsi.setTextSize(14); tIsi.setTextColor(Color.BLACK); tIsi.setPadding(0,0,0,20); l.addView(tIsi)
    local off = 0; local function tampil(o) local tgl = os.date("%Y-%m-%d", os.time() + (o * 86400)); if type(cfg.jadwalSebulan) == "table" and cfg.jadwalSebulan[tgl] then local j = cfg.jadwalSebulan[tgl]; tJudul.setText("Jadwal " .. formatTanggalIndo(tgl)); tIsi.setText("Subuh: " .. tambahMenit(j.Subuh, selisihWaktu("Subuh")) .. "\nTerbit: " .. j.Terbit .. "\nDhuha: " .. j.Dhuha .. "\nDzuhur: " .. tambahMenit(j.Dzuhur, selisihWaktu("Dzuhur")) .. "\nAshar: " .. tambahMenit(j.Ashar, selisihWaktu("Ashar")) .. "\nMaghrib: " .. tambahMenit(j.Maghrib, selisihWaktu("Maghrib")) .. "\nIsya: " .. tambahMenit(j.Isya, selisihWaktu("Isya"))) else tJudul.setText("Data tidak tersedia"); tIsi.setText("") end end
    local lNav = LinearLayout(ctxApp); lNav.setOrientation(0); btnLocal(lNav, "SEBELUMNYA", function() off = off - 1; tampil(off) end, "#FF9800", "#FFFFFF"); btnLocal(lNav, "HARI INI", function() off = 0; tampil(0) end, "#4CAF50", "#FFFFFF"); btnLocal(lNav, "SELANJUTNYA", function() off = off + 1; tampil(off) end, "#2196F3", "#FFFFFF"); l.addView(lNav)
    
    btnLocal(l, "KEMBALI KE MENU SEBELUMNYA", function() tutup(menuFiturLanjutan) end, "#D32F2F", "#FFFFFF")
    
    s.addView(l); d = AlertDialog.Builder(ctxApp).setTitle("Jadwal Harian").setView(s).create()
    d.setOnCancelListener(DialogInterface.OnCancelListener{onCancel = function() tutup(menuFiturLanjutan) end}); pcall(function() d.show() end); tampil(0)
end

menuPengaturanAudioMedia = function()
    local d; local s = ScrollView(ctxApp); local l = LinearLayout(ctxApp); l.setOrientation(1); l.setPadding(40,40,40,40); local navigasiAktif = false
    local function tutup(tujuan) if not navigasiAktif then navigasiAktif = true; pcall(function() d.dismiss() end); if tujuan then tugasTunda(150, tujuan) end end end
    
    btnLocal(l, "KEMBALI KE MENU SEBELUMNYA", function() tutup(menuFiturLanjutan) end, "#D32F2F", "#FFFFFF")
    
    local t1 = TextView(ctxApp); t1.setText("JALUR KELUARAN SUARA:"); t1.setTextColor(Color.BLUE); t1.setPadding(0,20,0,10); l.addView(t1)
    local function tgS(txt, strm) btnLocal(l, (cfg.audioStream == strm and "[ TERPILIH ] " or "") .. txt, function() cfg.audioStream = strm; simpanData(); tutup(menuPengaturanAudioMedia) end) end
    tgS("Audio Media", AudioManager.STREAM_MUSIC); tgS("Nada Dering", AudioManager.STREAM_RING); tgS("Alarm", AudioManager.STREAM_ALARM); tgS("Notifikasi", AudioManager.STREAM_NOTIFICATION)
    
    local t2 = TextView(ctxApp); t2.setText("VOLUME ADZAN KALI LIMA WAKTU ("..cfg.volAdzan.."%):"); t2.setTextColor(Color.BLUE); t2.setPadding(0,40,0,10); l.addView(t2)
    local lVolA = LinearLayout(ctxApp); lVolA.setOrientation(0)
    btnLocal(lVolA, " TURUNKAN 10% ", function() cfg.volAdzan = math.max(10, cfg.volAdzan - 10); simpanData(); tutup(menuPengaturanAudioMedia) end, "#FF9800", "#FFFFFF")
    btnLocal(lVolA, " NAIKKAN 10% ", function() cfg.volAdzan = math.min(100, cfg.volAdzan + 10); simpanData(); tutup(menuPengaturanAudioMedia) end, "#4CAF50", "#FFFFFF")
    local hsvA = HorizontalScrollView(ctxApp); hsvA.addView(lVolA); l.addView(hsvA)
    
    local t3 = TextView(ctxApp); t3.setText("VOLUME MUROTTAL & SISTEM ("..cfg.volMurottal.."%):"); t3.setTextColor(Color.BLUE); t3.setPadding(0,40,0,10); l.addView(t3)
    local lVolM = LinearLayout(ctxApp); lVolM.setOrientation(0)
    btnLocal(lVolM, " TURUNKAN 10% ", function() cfg.volMurottal = math.max(10, cfg.volMurottal - 10); simpanData(); tutup(menuPengaturanAudioMedia) end, "#FF9800", "#FFFFFF")
    btnLocal(lVolM, " NAIKKAN 10% ", function() cfg.volMurottal = math.min(100, cfg.volMurottal + 10); simpanData(); tutup(menuPengaturanAudioMedia) end, "#4CAF50", "#FFFFFF")
    local hsvM = HorizontalScrollView(ctxApp); hsvM.addView(lVolM); l.addView(hsvM)
    
    btnLocal(l, "KEMBALI KE MENU SEBELUMNYA", function() tutup(menuFiturLanjutan) end, "#D32F2F", "#FFFFFF")
    
    s.addView(l); d = AlertDialog.Builder(ctxApp).setTitle("Audio & Volume Cerdas").setView(s).create()
    d.setOnCancelListener(DialogInterface.OnCancelListener{onCancel = function() tutup(menuFiturLanjutan) end}); pcall(function() d.show() end)
end

menuVolumeCerdas = function()
    local d; local l = LinearLayout(ctxApp); l.setOrientation(1); l.setPadding(40,40,40,40); local navigasiAktif = false
    local function tutup(tujuan) if not navigasiAktif then navigasiAktif = true; pcall(function() d.dismiss() end); if tujuan then tugasTunda(150, tujuan) end end end
    
    btnLocal(l, "KEMBALI KE MENU SEBELUMNYA", function() tutup(menuFiturLanjutan) end, "#D32F2F", "#FFFFFF")
    
    btnLocal(l, (cfg.autoVolume and "[ ON ] By-pass Volume HP" or "[ OFF ] By-pass Volume HP"), function() cfg.autoVolume = not cfg.autoVolume; simpanData(); tutup(menuVolumeCerdas) end)
    btnLocal(l, (cfg.getarAwal and "[ ON ] Getar Awal Sholat" or "[ OFF ] Getar Awal Sholat"), function() cfg.getarAwal = not cfg.getarAwal; simpanData(); tutup(menuVolumeCerdas) end)
    
    btnLocal(l, "KEMBALI KE MENU SEBELUMNYA", function() tutup(menuFiturLanjutan) end, "#D32F2F", "#FFFFFF")
    
    d = AlertDialog.Builder(ctxApp).setTitle("Pengaturan Cerdas").setView(l).create()
    d.setOnCancelListener(DialogInterface.OnCancelListener{onCancel = function() tutup(menuFiturLanjutan) end}); pcall(function() d.show() end)
end

menuDiagnostik = function()
    local d; local l = LinearLayout(ctxApp); l.setOrientation(1); l.setPadding(40,40,40,40); local t = TextView(ctxApp); t.setTextColor(Color.BLACK); t.setTextSize(16); local navigasiAktif = false
    local function tutup(tujuan) if not navigasiAktif then navigasiAktif = true; pcall(function() d.dismiss() end); if tujuan then tugasTunda(150, tujuan) end end end
    
    btnLocal(l, "KEMBALI KE MENU SEBELUMNYA", function() tutup(menuFiturLanjutan) end, "#D32F2F", "#FFFFFF")
    
    local cM = 0; local ok, fs = pcall(function() return luajava.astable(File(pathPlugin).listFiles()) end); if ok and fs then cM = #fs end
    t.setText("1. API: " .. (cfg.idKota ~= "" and "TERHUBUNG" or "GAGAL") .. "\n2. Lokasi: " .. (cfg.lokasiDitemukan ~= "" and cfg.lokasiDitemukan or "KOSONG") .. "\n3. Audio Ditemukan: " .. cM .. " file\n4. Path: " .. pathPlugin .. "\n5. Murottal: " .. cfg.modeMurottal:upper() .. "\n6. TTS: " .. cfg.jenisSuaraTTS)
    l.addView(t); btnLocal(l, "CEK IZIN BATERAI", function() d.dismiss(); bukaPengaturanBaterai() end, "#E91E63", "#FFFFFF"); 
    
    btnLocal(l, "KEMBALI KE MENU SEBELUMNYA", function() tutup(menuFiturLanjutan) end, "#D32F2F", "#FFFFFF")
    
    d = AlertDialog.Builder(ctxApp).setTitle("Diagnostik").setView(l).create()
    d.setOnCancelListener(DialogInterface.OnCancelListener{onCancel = function() tutup(menuFiturLanjutan) end}); pcall(function() d.show() end)
end

bukaMenuPanduan = function()
    local d; local l = LinearLayout(ctxApp); l.setOrientation(1); l.setPadding(40,40,40,40); local navigasiAktif = false
    local function tutup(tujuan) if not navigasiAktif then navigasiAktif = true; pcall(function() d.dismiss() end); if tujuan then tugasTunda(150, tujuan) end end end
    
    btnLocal(l, "KEMBALI KE MENU SEBELUMNYA", function() tutup(menuFiturLanjutan) end, "#D32F2F", "#FFFFFF")
    
    local scroll = ScrollView(ctxApp); local t = TextView(ctxApp); t.setTextColor(Color.BLACK); t.setTextSize(14); t.setPadding(0,20,0,0)
    t.setText([[PANDUAN PENGGUNAAN JADWAL SALAT BY RENO

1. Pengaturan Lokasi: Buka Pengaturan Lokasi, pilih provinsi dan kota.
2. Sakelar Master: Di beranda, matikan tombol ini jika Anda ingin menghentikan seluruh sistem siaran secara instan.
3. Adzan & Tarhim: Anda bisa mematikan adzan waktu tertentu melalui menu Adzan & Tarhim.
4. Mode Khusyuk: Mengecilkan nada dering saat sholat berlangsung.
5. Selisih Waktu Manual: Di beranda, geser waktu Subuh, Dzuhur, Ashar, Maghrib, dan Isya maju atau mundur beberapa menit.]])
    scroll.addView(t); l.addView(scroll); 
    
    btnLocal(l, "KEMBALI KE MENU SEBELUMNYA", function() tutup(menuFiturLanjutan) end, "#D32F2F", "#FFFFFF")
    
    d = AlertDialog.Builder(ctxApp).setTitle("Panduan").setView(l).create()
    d.setOnCancelListener(DialogInterface.OnCancelListener{onCancel = function() tutup(menuFiturLanjutan) end}); pcall(function() d.show() end)
end

bukaMenuTentang = function()
    local d; local l = LinearLayout(ctxApp); l.setOrientation(1); l.setPadding(40,40,40,40); local navigasiAktif = false
    local function tutup(tujuan) if not navigasiAktif then navigasiAktif = true; pcall(function() d.dismiss() end); if tujuan then tugasTunda(150, tujuan) end end end
    
    btnLocal(l, "KEMBALI KE MENU SEBELUMNYA", function() tutup(menuFiturLanjutan) end, "#D32F2F", "#FFFFFF")
    
    local scroll = ScrollView(ctxApp); local t = TextView(ctxApp); t.setTextColor(Color.BLACK); t.setTextSize(14); t.setPadding(0,20,0,0)
    
    local teksTentang = "JADWAL SALAT BY RENO\n\n"
    teksTentang = teksTentang .. "Sistem asisten cerdas purna waktu untuk pengelolaan siaran masjid dan pengingat ibadah.\n\n"
    teksTentang = teksTentang .. "PENGEMBANG & SOURCE CODE:\nDikembangkan oleh Hamba Allah Codsos.\n\n"
    teksTentang = teksTentang .. "KREDIT & PENGHARGAAN TIM:\n"
    teksTentang = teksTentang .. "1. Mas Yeni Setiawan (Penguji VIP & Penasihat Utama atas saran dan idenya yang luar biasa)\n"
    teksTentang = teksTentang .. "2. Pak Ragil (Penasihat Senior)\n"
    teksTentang = teksTentang .. "3. Kang Supri (Tim Penguji)\n"
    teksTentang = teksTentang .. "4. Kang Datsun (Tim Evaluasi Aksesibilitas)\n\n"
    teksTentang = teksTentang .. "LISENSI MUTLAK (DIGITAL WAQAF):\nSource Code diwakafkan 100% GRATIS untuk umat. Dilarang memperjualbelikan atau memonetisasi sistem ini.\n\n"
    teksTentang = teksTentang .. "KATA PENUTUP:\nSistem ini adalah wujud syiar dakwah yang menembus batas keterbatasan visual. Semoga setiap kumandang adzan dari mesin ini menjadi saksi amal jariyah kita kelak. Hasbunallah wa ni'mal wakil."
    
    t.setText(teksTentang)
    scroll.addView(t); l.addView(scroll); 
    
    btnLocal(l, "KEMBALI KE MENU SEBELUMNYA", function() tutup(menuFiturLanjutan) end, "#D32F2F", "#FFFFFF")
    
    d = AlertDialog.Builder(ctxApp).setTitle("Tentang Aplikasi").setView(l).create()
    d.setOnCancelListener(DialogInterface.OnCancelListener{onCancel = function() tutup(menuFiturLanjutan) end}); pcall(function() d.show() end)
end

menuSakelarSunnah = function()
    local d; local s = ScrollView(ctxApp); local l = LinearLayout(ctxApp); l.setOrientation(1); l.setPadding(40,40,40,40); local navigasiAktif = false
    local function tutup(tujuan) if not navigasiAktif then navigasiAktif = true; pcall(function() d.dismiss() end); if tujuan then tugasTunda(150, tujuan) end end end
    
    btnLocal(l, "KEMBALI KE MENU SEBELUMNYA", function() tutup(menuFiturLanjutan) end, "#D32F2F", "#FFFFFF")
    
    local function tg(txt, key) btnLocal(l, (cfg[key] and "[ ON ] " or "[ OFF ] ") .. txt, function() cfg[key] = not cfg[key]; simpanData(); tutup(menuSakelarSunnah) end, (cfg[key] and "#4CAF50" or "#9E9E9E"), "#FFFFFF") end
    tg("Mode Musafir (Hak Jamak/Qashar)", "s_musafir")
    tg("Mode Khusyuk (Getar)", "s_khusyuk"); tg("Kehati-hatian (15 mnt akhir)", "s_kehatihatian")
    tg("Peringatan Pra-Terbit (10 Mnt)", "s_preterbit")
    tg("Alarm Waktu Terbit (Syuruq)", "s_terbit")
    tg("Alarm Dhuha", "s_dhuha"); tg("Alarm Tahajud", "s_tahajud"); tg("Pengingat Puasa Lengkap", "s_puasa"); tg("Imsak", "s_imsak"); tg("Protokol Jumat", "s_jumat"); tg("Laporan Bisu Tiap Jam", "s_jam")
    
    local tM = TextView(ctxApp); tM.setText("SAKELAR MUROTTAL PRA-ADZAN (lamanya diatur di Durasi Waktu Jeda):"); tM.setTextColor(Color.BLUE); tM.setPadding(0,30,0,10); l.addView(tM)
    tg("Murottal Subuh", "murottal_subuh_on"); tg("Murottal Dzuhur", "murottal_dzuhur_on"); tg("Murottal Ashar", "murottal_ashar_on")
    tg("Murottal Maghrib", "murottal_maghrib_on"); tg("Murottal Isya", "murottal_isya_on")
    
    local tI = TextView(ctxApp); tI.setText("SAKELAR IQOMAH:"); tI.setTextColor(Color.BLUE); tI.setPadding(0,30,0,10); l.addView(tI)
    tg("Iqomah", "iqomah_on")
    
    btnLocal(l, "KEMBALI KE MENU SEBELUMNYA", function() tutup(menuFiturLanjutan) end, "#D32F2F", "#FFFFFF")
    
    s.addView(l); d = AlertDialog.Builder(ctxApp).setTitle("Sakelar Ibadah Lainnya").setView(s).create()
    d.setOnCancelListener(DialogInterface.OnCancelListener{onCancel = function() tutup(menuFiturLanjutan) end}); pcall(function() d.show() end)
end

menuTesAudio = function()
    local d; local s = ScrollView(ctxApp); local l = LinearLayout(ctxApp); l.setOrientation(1); l.setPadding(40,40,40,40); local navigasiAktif = false
    local function tutup(tujuan) if not navigasiAktif then navigasiAktif = true; pcall(function() d.dismiss() end); if tujuan then tugasTunda(150, tujuan) end end end
    
    btnLocal(l, "KEMBALI KE MENU SEBELUMNYA", function() tutup(menuFiturLanjutan) end, "#D32F2F", "#FFFFFF")
    
    btnLocal(l, "HENTIKAN SEMUA AUDIO", function() hentikanAudioDanSimpan(); infoVisual("Audio dihentikan.") end, "#E91E63", "#FFFFFF")
    
    local t1 = TextView(ctxApp); t1.setText("UJI KINERJA SISTEM SUARA:"); t1.setTextColor(Color.BLUE); t1.setPadding(0,40,0,10); l.addView(t1)
    btnLocal(l, "1. UJI SUARA TTS", function() bicaraGoogleTTS("Sistem asisten suara merespons normal.", true) end)
    btnLocal(l, "2. BUMPER / PEMBUKA", function() tutup(function() putarAudio("sistem", "bumper", menuTesAudio) end) end)
    btnLocal(l, "3. TARHIM (OTOMATIS / ACAK)", function() tutup(function() putarAudio("sistem", "tarhim", menuTesAudio) end) end)
    
    local t2 = TextView(ctxApp); t2.setText("UJI MUROTTAL:"); t2.setTextColor(Color.BLUE); t2.setPadding(0,40,0,10); l.addView(t2)
    btnLocal(l, "4. MUROTTAL ACAK (MURNI)", function() tutup(function() putarAudio("murottal", "", menuTesAudio) end) end)
    btnLocal(l, "5. MUROTTAL SUBUH", function() tutup(function() putarAudio("murottal", "subuh", menuTesAudio) end) end)
    btnLocal(l, "6. MUROTTAL AL-JUMU'AH", function() tutup(function() putarAudio("murottal", "aljumuah", menuTesAudio) end) end)
    
    local t3 = TextView(ctxApp); t3.setText("UJI ALARM WAKTU KHUSUS:"); t3.setTextColor(Color.BLUE); t3.setPadding(0,40,0,10); l.addView(t3)
    btnLocal(l, "7. PERINGATAN TERBIT (10 MNT)", function() tutup(function() putarAudioDenganCallback("sistem", "peringatanterbit", nil, menuTesAudio) end) end)
    btnLocal(l, "8. WAKTU TERBIT (SYURUQ)", function() tutup(function() putarAudioDenganCallback("sistem", "terbit", nil, menuTesAudio) end) end)
    btnLocal(l, "9. ALARM DHUHA", function() tutup(function() putarAudioDenganCallback("sistem", "dhuha", nil, menuTesAudio) end) end)
    btnLocal(l, "10. ALARM TAHAJUD", function() tutup(function() putarAudioDenganCallback("sistem", "tahajud", nil, menuTesAudio) end) end)
    btnLocal(l, "11. ALARM SAHUR", function() tutup(function() putarAudioDenganCallback("sistem", "sahur", nil, menuTesAudio) end) end)
    
    local t4 = TextView(ctxApp); t4.setText("UJI ADZAN DAN IQOMAH (BERDASARKAN JADWAL ANDA):"); t4.setTextColor(Color.BLUE); t4.setPadding(0,40,0,10); l.addView(t4)
    btnLocal(l, "12. UJI ADZAN SUBUH", function() tutup(function() putarAudio("adzan", "Subuh", menuTesAudio) end) end)
    btnLocal(l, "13. UJI ADZAN DZUHUR", function() tutup(function() putarAudio("adzan", "Dzuhur", menuTesAudio) end) end)
    btnLocal(l, "14. UJI ADZAN ASHAR", function() tutup(function() putarAudio("adzan", "Ashar", menuTesAudio) end) end)
    btnLocal(l, "15. UJI ADZAN MAGHRIB", function() tutup(function() putarAudio("adzan", "Maghrib", menuTesAudio) end) end)
    btnLocal(l, "16. UJI ADZAN ISYA", function() tutup(function() putarAudio("adzan", "Isya", menuTesAudio) end) end)
    btnLocal(l, "17. UJI IQOMAH", function() tutup(function() putarAudio("sistem", "iqomah", menuTesAudio) end) end)
    
    btnLocal(l, "KEMBALI KE MENU SEBELUMNYA", function() tutup(menuFiturLanjutan) end, "#D32F2F", "#FFFFFF")

    s.addView(l); d = AlertDialog.Builder(ctxApp).setTitle("Dasbor Tes Audio Terpadu").setView(s).create()
    d.setOnCancelListener(DialogInterface.OnCancelListener{onCancel = function() tutup(menuFiturLanjutan) end}); pcall(function() d.show() end)
end

bukaMenuPilihSuaraTTS = function()
    jalankanDiUI(function()
        local ds = {}; if _G.NidaulGoogleTTS then local v = _G.NidaulGoogleTTS.getVoices(); if v then local i = v.iterator(); local c = 1; while i.hasNext() do local voice = i.next(); local n = voice.getName(); if n:lower():find("id%-id") then table.insert(ds, {label="Suara "..c.." ("..(n:lower():find("network") and "Jaringan" or "Lokal")..")", nilai=n}); c=c+1 end end end end; table.insert(ds, {label="Default Sistem", nilai="default"})
        local d; local s = ScrollView(ctxApp); local l = LinearLayout(ctxApp); l.setOrientation(1); l.setPadding(40,40,40,40); local navigasiAktif = false
        local function tutup(tujuan) if not navigasiAktif then navigasiAktif = true; pcall(function() d.dismiss() end); if tujuan then tugasTunda(150, tujuan) end end end
        
        btnLocal(l, "KEMBALI KE MENU SEBELUMNYA", function() tutup(menuFiturLanjutan) end, "#D32F2F", "#FFFFFF")
        
        for _, item in ipairs(ds) do btnLocal(l, (item.nilai == cfg.jenisSuaraTTS and "[ TERPILIH ] " or "") .. item.label, function() cfg.jenisSuaraTTS = item.nilai; simpanData(); aturSuaraTTS(); bicaraGoogleTTS("Uji coba suara.", true); tutup(menuFiturLanjutan) end) end
        
        btnLocal(l, "KEMBALI KE MENU SEBELUMNYA", function() tutup(menuFiturLanjutan) end, "#D32F2F", "#FFFFFF")
        
        s.addView(l); d = AlertDialog.Builder(ctxApp).setTitle("Suara TTS").setView(s).create()
        d.setOnCancelListener(DialogInterface.OnCancelListener{onCancel = function() tutup(menuFiturLanjutan) end}); pcall(function() d.show() end)
    end)
end

menuProfilLokasi = function()
    local d; local s = ScrollView(ctxApp); local l = LinearLayout(ctxApp); l.setOrientation(1); l.setPadding(40,40,40,40); local navigasiAktif = false
    local function tutup(tujuan) if not navigasiAktif then navigasiAktif = true; pcall(function() d.dismiss() end); if tujuan then tugasTunda(150, tujuan) end end end
    
    btnLocal(l, "KEMBALI KE MENU SEBELUMNYA", function() tutup(menuFiturLanjutan) end, "#D32F2F", "#FFFFFF")
    
    if cfg.kota ~= "Belum Diatur" and cfg.idKota ~= "" then btnLocal(l, "SIMPAN PROFIL", function() local nama = cfg.kota; if cfg.profilLokasi[nama] then return end; cfg.profilLokasi[nama] = {kota=cfg.kota, idKota=cfg.idKota, lokasi=cfg.lokasiDitemukan}; simpanData(); infoVisual("Profil disimpan."); tutup(menuProfilLokasi) end, "#4CAF50", "#FFFFFF") end
    for nama, data in pairs(cfg.profilLokasi) do btnLocal(l, nama .. " (" .. data.lokasi .. ")", function() cfg.kota = data.kota; cfg.lokasiOtomatis = false; cfg.idKota = data.idKota; cfg.lokasiDitemukan = data.lokasi; sinkronisasiJadwalV3Cerdas(data.kota, function(s) end); tutup(tampilkanMenuUtama) end); btnLocal(l, "  [HAPUS " .. nama .. "]", function() cfg.profilLokasi[nama] = nil; simpanData(); tutup(menuProfilLokasi) end, "#F44336", "#FFFFFF") end
    
    btnLocal(l, "KEMBALI KE MENU SEBELUMNYA", function() tutup(menuFiturLanjutan) end, "#D32F2F", "#FFFFFF")
    
    s.addView(l); d = AlertDialog.Builder(ctxApp).setTitle("Profil Lokasi").setView(s).create()
    d.setOnCancelListener(DialogInterface.OnCancelListener{onCancel = function() tutup(menuFiturLanjutan) end}); pcall(function() d.show() end)
end

menuFiturLanjutan = function()
    jalankanDiUI(function()
        local d; local s = ScrollView(ctxApp); local l = LinearLayout(ctxApp); l.setOrientation(1); l.setPadding(40,40,40,40); local navigasiAktif = false
        local function tutup(tujuan) if not navigasiAktif then navigasiAktif = true; pcall(function() d.dismiss() end); if tujuan then tugasTunda(150, tujuan) end end end
        
        btnLocal(l, "KEMBALI KE MENU UTAMA", function() tutup(tampilkanMenuUtama) end, "#D32F2F", "#FFFFFF")
        
        local tAlat = TextView(ctxApp); tAlat.setText("ALAT BANTU IBADAH:"); tAlat.setTextColor(Color.BLUE); tAlat.setPadding(0,30,0,10); l.addView(tAlat)
        btnLocal(l, "1. RADAR KIBLAT SUARA", function() tutup(menuRadarKiblat) end)
        btnLocal(l, "2. KALENDER HIJRIYAH (BISA DIKOREKSI)", function() tutup(menuKalenderHijriyah) end)
        btnLocal(l, "3. KALENDER JAWA", function() tutup(menuKalenderJawa) end)
        btnLocal(l, "4. JADWAL HARIAN LENGKAP", function() tutup(menuJadwalBulanan) end)
        btnLocal(l, "5. SETEL ALARM PRIBADI", function() tutup(menuAlarmPribadi) end)

        local tSet = TextView(ctxApp); tSet.setText("PENGATURAN MESIN & SUARA:"); tSet.setTextColor(Color.BLUE); tSet.setPadding(0,30,0,10); l.addView(tSet)
        btnLocal(l, "6. SAKELAR IBADAH LAINNYA", function() tutup(menuSakelarSunnah) end)
        btnLocal(l, "7. AUDIO & VOLUME", function() tutup(menuPengaturanAudioMedia) end)
        btnLocal(l, "8. DURASI WAKTU JEDA", function() tutup(menuPengaturanDurasi) end)
        btnLocal(l, "9. PENGATURAN CERDAS", function() tutup(menuVolumeCerdas) end)
        btnLocal(l, "10. PILIHAN SUARA TTS", function() tutup(bukaMenuPilihSuaraTTS) end)
        
        
        local tLain = TextView(ctxApp); tLain.setText("SISTEM & PEMELIHARAAN:"); tLain.setTextColor(Color.BLUE); tLain.setPadding(0,30,0,10); l.addView(tLain)
        btnLocal(l, "11. TES AUDIO TERPADU", function() tutup(menuTesAudio) end)
        btnLocal(l, "12. PROFIL LOKASI TERSIMPAN", function() tutup(menuProfilLokasi) end)
        btnLocal(l, "13. DIAGNOSTIK MESIN", function() tutup(menuDiagnostik) end)
        btnLocal(l, "14. PANDUAN PENGGUNAAN", function() tutup(bukaMenuPanduan) end)
        btnLocal(l, "15. TENTANG APLIKASI", function() tutup(bukaMenuTentang) end)
        
        btnLocal(l, "KEMBALI KE MENU UTAMA", function() tutup(tampilkanMenuUtama) end, "#D32F2F", "#FFFFFF")
        
        s.addView(l); d = AlertDialog.Builder(ctxApp).setTitle("Fitur Lanjutan & Info").setView(s).create()
        d.setOnCancelListener(DialogInterface.OnCancelListener{onCancel = function() tutup(tampilkanMenuUtama) end}); pcall(function() d.show() end)
    end)
end

menuSelisihManual = function()
    local d; local s = ScrollView(ctxApp); local l = LinearLayout(ctxApp); l.setOrientation(1); l.setPadding(40,40,40,40); local navigasiAktif = false
    local function tutup(tujuan) if not navigasiAktif then navigasiAktif = true; pcall(function() d.dismiss() end); if tujuan then tugasTunda(150, tujuan) end end end

    btnLocal(l, "KEMBALI KE MENU UTAMA", function() tutup(tampilkanMenuUtama) end, "#D32F2F", "#FFFFFF")

    local tInfo = TextView(ctxApp); tInfo.setText("Geser waktu salat maju atau mundur (dalam menit) dari jadwal asli. Adzan, tarhim, murottal, dan iqomah ikut menyesuaikan. Batas -60 sampai +60 menit.")
    tInfo.setTextColor(Color.BLACK); tInfo.setPadding(0,10,0,10); l.addView(tInfo)

    local jdw = type(cfg.jadwalSebulan) == "table" and cfg.jadwalSebulan[os.date("%Y-%m-%d")] or nil
    local function teksSel(v) if v > 0 then return "maju " .. v .. " menit" elseif v < 0 then return "mundur " .. (-v) .. " menit" else return "tanpa selisih" end end

    for _, nama in ipairs({"Subuh", "Dzuhur", "Ashar", "Maghrib", "Isya"}) do
        local sel = cfg.selisih[nama] or 0
        local teks = nama .. ": " .. teksSel(sel)
        if jdw and jdw[nama] and jdw[nama] ~= "" then teks = teks .. "\nAsli " .. jdw[nama] .. ", dipakai " .. tambahMenit(jdw[nama], selisihWaktu(nama)) end
        local tv = TextView(ctxApp); tv.setText(teks); tv.setTextColor(Color.BLUE); tv.setTextSize(16); tv.setPadding(0,24,0,8); l.addView(tv)
        local lH = LinearLayout(ctxApp); lH.setOrientation(0)
        local function ubah(delta)
            local baru = (delta == 0) and 0 or math.max(-60, math.min(60, (cfg.selisih[nama] or 0) + delta))
            cfg.selisih[nama] = baru; simpanData()
            local ucap = nama .. " " .. teksSel(baru)
            if jdw and jdw[nama] and jdw[nama] ~= "" then ucap = ucap .. ", jadi " .. tambahMenit(jdw[nama], selisihWaktu(nama)) end
            bicaraGoogleTTS(ucap, true)
            tutup(menuSelisihManual)
        end
        btnLocal(lH, "Mundur 5", function() ubah(-5) end, "#FF9800", "#FFFFFF")
        btnLocal(lH, "Mundur 1", function() ubah(-1) end, "#FF9800", "#FFFFFF")
        btnLocal(lH, "Nol", function() ubah(0) end, "#9E9E9E", "#FFFFFF")
        btnLocal(lH, "Maju 1", function() ubah(1) end, "#4CAF50", "#FFFFFF")
        btnLocal(lH, "Maju 5", function() ubah(5) end, "#4CAF50", "#FFFFFF")
        local hsv = HorizontalScrollView(ctxApp); hsv.addView(lH); l.addView(hsv)
    end

    btnLocal(l, "NOLKAN SEMUA SELISIH", function()
        for _, n in ipairs({"Subuh", "Dzuhur", "Ashar", "Maghrib", "Isya"}) do cfg.selisih[n] = 0 end
        simpanData(); bicaraGoogleTTS("Semua selisih waktu dinolkan.", true); tutup(menuSelisihManual)
    end, "#D32F2F", "#FFFFFF")
    btnLocal(l, "KEMBALI KE MENU UTAMA", function() tutup(tampilkanMenuUtama) end, "#D32F2F", "#FFFFFF")

    s.addView(l); d = AlertDialog.Builder(ctxApp).setTitle("Selisih Waktu Manual").setView(s).create()
    d.setOnCancelListener(DialogInterface.OnCancelListener{onCancel = function() tutup(tampilkanMenuUtama) end}); pcall(function() d.show() end)
end

menuPengaturanLokasi = function()
    local d; local navigasiAktif = false
    local function tutup(tujuan) if not navigasiAktif then navigasiAktif = true; pcall(function() d.dismiss() end); if tujuan then tugasTunda(150, tujuan) end end end

    -- tampilan dari layout.aly (satu folder dengan main.lua)
    local ok, tampilan = pcall(loadlayout, "layout")
    if not ok or not tampilan then
        infoVisual("layout.aly tidak ditemukan atau salah.")
        return
    end
    local sP, sK = lokSpProvinsi, lokSpKota
    sP.setAdapter(ArrayAdapter(ctxApp, android.R.layout.simple_list_item_1, jA(pList)))
    _G.KotaTerpilihSementara = kData[pList[1]][1]

    sP.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{onItemSelected=function(p,v,pos,id) local pP=pList[pos+1]; local dK=kData[pP]; sK.setAdapter(ArrayAdapter(ctxApp, android.R.layout.simple_list_item_1, jA(dK))); _G.KotaTerpilihSementara=dK[1] end, onNothingSelected=function(p) end})
    sK.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{onItemSelected=function(p,v,pos,id) local dK=kData[pList[sP.getSelectedItemPosition()+1]]; if dK then _G.KotaTerpilihSementara=dK[pos+1] end end, onNothingSelected=function(p) end})

    lokBtnKembaliAtas.onClick = function() tutup(tampilkanMenuUtama) end
    lokBtnKembaliBawah.onClick = function() tutup(tampilkanMenuUtama) end
    lokBtnSimpan.onClick = function()
        local kF = _G.KotaTerpilihSementara; if kF == nil or kF == "" then return end
        cfg.kota = kF; cfg.lokasiOtomatis = false; bicaraGoogleTTS("Mencari jadwal untuk " .. kF, true)
        sinkronisasiJadwalV3Cerdas(kF, function(s, p) if s then infoVisual("Jadwal tersimpan.") else infoVisual("Gagal menarik jadwal.") end; tutup(tampilkanMenuUtama) end, false)
    end

    d = AlertDialog.Builder(ctxApp).setTitle("Pilih Wilayah").setView(tampilan).create()
    d.setOnCancelListener(DialogInterface.OnCancelListener{onCancel = function() tutup(tampilkanMenuUtama) end}); pcall(function() d.show() end)
end

-- ===================== MEMORI MUROTTAL SUBUH - ISYA =====================
-- Lapisan tambahan: tiap waktu salat mengingat berkas murottal + menit terakhir,
-- lalu melanjutkannya di waktu yang sama berikutnya. Fungsi lama tidak diubah, hanya dibungkus.
_G.DaftarWaktuMemori = {"Subuh", "Dzuhur", "Ashar", "Maghrib", "Isya"}

function waktuMemori(jenis, paramWaktu)
    if jenis ~= "murottal" then return nil end
    local k = tostring(paramWaktu or ""):lower():gsub("[%s%-%_]", "")
    for _, n in ipairs(_G.DaftarWaktuMemori) do
        if k == n:lower() then
            if os.date("%w") == "4" and (n == "Maghrib" or n == "Isya") then return nil end -- malam Jumat: Yasin
            return n
        end
    end
    return nil
end

-- 1) Pilih berkas: pakai berkas yang diingat bila ada
local radarAsli = radarAudioPintar
function radarAudioPintar(kataKunci)
    local ok, hasil = pcall(function()
        local k = tostring(kataKunci or "")
        for _, n in ipairs(_G.DaftarWaktuMemori) do
            if k == n:lower() then
                local m = cfg.memMurottal[n]
                if m and m.path and m.path ~= "" and File(m.path).exists() then return m.path end
            end
        end
        return nil
    end)
    if ok and hasil then return hasil end
    return radarAsli(kataKunci)
end

-- 2) Putar: lanjut dari menit yang diingat
local putarAsli = putarAudio
function putarAudio(jenis, paramWaktu, menuAsal, pathPaksa)
    if tundaMurottalPas(jenis, paramWaktu, menuAsal, pathPaksa) then return end
    pcall(hentikanAudioDanSimpan) -- simpan memori audio yang sedang jalan lebih dulu
    if jenis == "murottal" then
        local kk = tostring(paramWaktu or ""):lower()
        for _, nn in ipairs(_G.DaftarWaktuMemori) do if kk == nn:lower() then _G.MurottalRantai = {waktu = nn, t = os.time()} end end
    end
    local w = waktuMemori(jenis, paramWaktu)
    if not w then _G.MurottalMem = nil; return putarAsli(jenis, paramWaktu, menuAsal, pathPaksa) end
    local modeLama, pathLama, posLama = cfg.modeMurottal, cfg.lastMurottalPath, cfg.lastMurottalPos
    local m = cfg.memMurottal[w]
    cfg.modeMurottal = "sambung"
    if m and m.path and m.path ~= "" then cfg.lastMurottalPath = m.path; cfg.lastMurottalPos = m.pos or 0
    else cfg.lastMurottalPath = ""; cfg.lastMurottalPos = 0 end
    pcall(putarAsli, jenis, paramWaktu, menuAsal, pathPaksa)
    local dipakai = cfg.lastMurottalPath
    cfg.modeMurottal, cfg.lastMurottalPath, cfg.lastMurottalPos = modeLama, pathLama, posLama
    if dipakai and dipakai ~= "" and File(dipakai).exists() then
        _G.MurottalMem = {waktu = w, path = dipakai, t = os.time()}
    else
        _G.MurottalMem = nil
    end
end

-- 3) Berhenti: simpan menit terakhir; kalau sudah tamat, surat berikutnya dipilih baru
--    dan (mode otomatis) murottal yang tamat langsung disambung tarhim
local hentikanAsli = hentikanAudioDanSimpan
function hentikanAudioDanSimpan()
    pcall(function()
        local main = false
        pcall(function() main = (_G.mpSistem and _G.mpSistem.isPlaying()) and true or false end)
        local mm = _G.MurottalMem
        if mm then
            if main then
                local pos = _G.mpSistem.getCurrentPosition(); local dur = _G.mpSistem.getDuration()
                if dur and dur > 0 and pos >= dur - 3000 then cfg.memMurottal[mm.waktu] = {path = "", pos = 0}
                else cfg.memMurottal[mm.waktu] = {path = mm.path, pos = math.floor(pos)} end
                _G.MurottalMem = nil; simpanData()
            elseif os.time() - mm.t > 8 then
                cfg.memMurottal[mm.waktu] = {path = "", pos = 0}
                _G.MurottalMem = nil; simpanData()
            end
        end
        local mr = _G.MurottalRantai
        if mr then
            if main then
                _G.MurottalRantai = nil -- dihentikan paksa / diganti audio lain: tidak disambung otomatis
            elseif os.time() - mr.t > 8 then
                _G.MurottalRantai = nil -- murottal tamat sendiri
                local w = mr.waktu
                tugasTunda(200, function() pcall(rantaiTarhim, w) end)
            end
        end
    end)
    return hentikanAsli()
end

-- 4) Hitungan sisa durasi untuk jadwal otomatis ikut menit yang diingat
--    (mode otomatis: cadangan dipotong 7 detik; sisa selisih diserap penundaan pas di awal murottal)
local sisaAsli = sisaMurottalMs
function sisaMurottalMs(info)
    local ok, hasil = pcall(function()
        if info and info.ap and not info.spesial then
            for _, n in ipairs(_G.DaftarWaktuMemori) do
                local m = cfg.memMurottal[n]
                if m and m.path == info.ap and (m.pos or 0) > 0 then
                    return math.max((info.durMs or 0) - m.pos, 0)
                end
            end
        end
        return nil
    end)
    local ms = (ok and hasil) or sisaAsli(info)
    pcall(function()
        if ms and ms > 10000 and info and not info.spesial and murottalOto() and tarhimOto() then ms = ms - 7000 end
    end)
    return ms
end

-- ===== RANTAI OTOMATIS: murottal -> tarhim -> adzan tanpa jeda (jeda iqomah tetap) =====
function sisaKeAdzan(n)
    local tgl = os.date("%Y-%m-%d")
    local jdw = (type(cfg.jadwalSebulan) == "table") and cfg.jadwalSebulan[tgl] or nil
    if not jdw or not jdw[n] or jdw[n] == "" then return nil end
    local wStr = tambahMenit(jdw[n], selisihWaktu(n))
    local tm = hitungMenitAbsolut(wStr)
    if tm == -1 then return nil end
    local t = os.date("*t"); local skr = t.hour * 3600 + t.min * 60 + t.sec
    return (tm * 60 - skr + 86400) % 86400, wStr, tgl
end

-- tarhim: potong cadangan waktu tetap (6 detik) dan jeda bawaan agar pas menyambung adzan
local siapTarhimAsli = siapkanTarhim
function siapkanTarhim(nama, tglIni)
    local info = siapTarhimAsli(nama, tglIni)
    pcall(function()
        if info and not info.dipangkas and tarhimOto() then
            info.dipangkas = true
            local tts = math.max(2.5, string.len(info.teks or "") * 0.1)
            info.lead = math.ceil((info.durMs or 0) / 1000 + 0.5 + tts + 3)
        end
    end)
    return info
end

function leadTarhimPas(info)
    return (info.durMs or 0) / 1000 + 0.5 + math.max(2.5, string.len(info.teks or "") * 0.1)
end

-- Murottal otomatis: bila mulai terlalu awal, tunda sebentar SEBELUM murottal (bukan di antara murottal-tarhim-adzan)
function tundaMurottalPas(jenis, paramWaktu, menuAsal, pathPaksa)
    if jenis ~= "murottal" or _G.SlackLewat then return false end
    local ok, hasil = pcall(function()
        if not (cfg.master_aktif and murottalOto() and tarhimOto()) then return false end
        local kk = tostring(paramWaktu or ""):lower(); local n = nil
        for _, nn in ipairs(_G.DaftarWaktuMemori) do if kk == nn:lower() then n = nn end end
        if not n or not cfg["tarhim_" .. kk .. "_on"] then return false end
        local sisa, wStr, tgl = sisaKeAdzan(n); if not sisa then return false end
        local path = pathPaksa or radarAudioPintar(kk); if not path then return false end
        local durMs = durasiFileMs(path); if not durMs or durMs <= 0 then return false end
        local pos = 0; local m = cfg.memMurottal[n]
        if m and m.path == path then pos = m.pos or 0 end
        local info = siapkanTarhim(n, tgl); if not info then return false end
        local slack = sisa - ((durMs - pos) / 1000 + leadTarhimPas(info))
        if slack > 1.5 and slack <= 60 then
            tugasTunda(math.floor(slack * 1000), function()
                _G.SlackLewat = true
                pcall(putarAudio, jenis, paramWaktu, menuAsal, pathPaksa)
                _G.SlackLewat = nil
            end)
            return true
        end
        return false
    end)
    return ok and hasil == true
end

function jalankanTarhim(ap, judul, teks)
    _G.TarhimBerjalan = true; _G.TarhimMulai = os.time()
    local oto = tarhimOto()
    local murJalan = false
    pcall(function() murJalan = (_G.mpSistem and _G.mpSistem.isPlaying()) and true or false end)
    local n = tostring(judul or ""):match("^Tarhim%s+(%a+)")
    -- tanpa murottal sebelumnya: tunda sebentar agar tarhim selesai tepat di waktu adzan
    local tambah = 0
    if oto and not murJalan and n then
        pcall(function()
            local sisa = sisaKeAdzan(n)
            local tgl = os.date("%Y-%m-%d")
            local info = siapkanTarhim(n, tgl)
            if sisa and info then
                local slack = sisa - leadTarhimPas(info)
                if slack > 1.5 and slack <= 60 then tambah = math.floor(slack * 1000) end
            end
        end)
    end
    hentikanAudioDanSimpan()
    local jeda1 = (oto and not murJalan) and 300 or 1700
    local jeda2 = oto and 200 or 1500
    tugasTunda(jeda1 + tambah, function()
        bicaraGoogleTTS(teks or dapatkanTeksVarian("Tarhim"), true, function()
            tugasTunda(jeda2, function()
                putarAudioFileLangsung(ap, judul, "sistem", nil, function()
                    _G.TarhimBerjalan = false
                    if oto and n then tugasTunda(50, function() pcall(rantaiAdzan, n) end) end
                end)
            end)
        end)
    end)
end

function rantaiTarhim(n)
    if not (cfg.master_aktif and murottalOto() and tarhimOto()) then return end
    if not cfg["tarhim_" .. n:lower() .. "_on"] then return end
    if n == "Dzuhur" and cfg.s_jumat and os.date("%w") == "5" then return end
    local sisa, wStr, tgl = sisaKeAdzan(n)
    if not sisa then return end
    local info = siapkanTarhim(n, tgl)
    if not info then return end
    if sisa > info.lead + 25 or sisa < 30 then return end
    local kunci = "TARHIM_" .. n .. tgl
    if _G.GembokAbsolut[kunci] then return end
    _G.GembokAbsolut[kunci] = true; simpanGembok()
    jalankanTarhim(info.ap, "Tarhim " .. n, info.teks)
end

-- Adzan tetap mengikuti jadwal: dimulai tepat di jam adzan (selisih kecil dari tarhim ditunggu / disusul)
function rantaiAdzan(n)
    if not (cfg.master_aktif and tarhimOto()) then return end
    if not cfg["adzan_" .. n:lower() .. "_on"] then return end
    if n == "Dzuhur" and cfg.s_jumat and os.date("%w") == "5" then return end
    local sisa, wStr, tgl = sisaKeAdzan(n)
    if not sisa then return end
    local telat = (sisa > 86000) and (86400 - sisa) or nil   -- tarhim selesai sedikit lewat jadwal
    if not telat and sisa > 8 then return end                 -- terlalu jauh dari jadwal: serahkan ke jadwal biasa
    local kunci = "ADZ_" .. n .. tgl
    if _G.GembokAbsolut[kunci] then return end
    if telat and telat > 20 then return end
    _G.GembokAbsolut[kunci] = true; simpanGembok()
    local tunggu = telat and 0 or math.max(0, math.floor(sisa * 1000) - 450)
    tugasTunda(tunggu, function()
        pcall(function()
            hentikanAudioDanSimpan(); eksekusiModeKhusyuk(cfg.durasiKhusyuk, n)
            if cfg.iqomah_on then pcall(function() if _G.IqomahWakeLock and not _G.IqomahWakeLock.isHeld() then _G.IqomahWakeLock.acquire((cfg.waktuIqomah + 2) * 60000) end end) end
            eksekusiAutoVolume(function()
                tugasTunda(400, function() putarAudio("adzan", n); kembalikanVolume() end)
            end)
        end)
    end)
    if cfg.iqomah_on then _G.GembokAbsolut["IQOMAH_" .. n .. tgl] = tambahMenit(wStr, cfg.waktuIqomah); simpanGembok() end
end
-- =======================================================================================

function formatMenitDetik(ms)
    local t = math.floor((ms or 0) / 1000)
    return string.format("%d:%02d", math.floor(t / 60), t % 60)
end

-- Daftar berkas murottal yang bisa dipilih (bukan adzan/tarhim/arham/bumper/iqomah dst.)
function dapatkanDaftarMurottal()
    local arrNama = {"[ ACAK / OTOMATIS ]"}
    local arrPath = {""}
    pcall(function()
        local sudah, fs = {}, {}
        -- sapu folder beserta semua subfolder di dalamnya (maks 4 tingkat), semua berkas audio ikut terbaca
        local function sapu(folder, akar, tingkat)
            if tingkat > 4 or #fs >= 500 then return end
            local ok, ls = pcall(function() return folder.listFiles() end)
            if not ok or not ls then return end
            local ok2, arr = pcall(function() return luajava.astable(ls) end)
            local n = (ok2 and arr) and #arr or ls.length
            for i = 0, n - 1 do
                local v = (ok2 and arr) and arr[i + 1] or ls[i]
                if v.isDirectory() then
                    sapu(v, akar, tingkat + 1)
                elseif v.isFile() then
                    local name = v.getName():lower()
                    if name:match("%.mp3$") or name:match("%.ogg$") or name:match("%.m4a$") or name:match("%.wav$") then
                        local full = v.getAbsolutePath()
                        if not sudah[full] then
                            sudah[full] = true
                            local rel = full:sub(#akar + 1)
                            fs[#fs + 1] = {path = full, label = rel}
                        end
                    end
                end
            end
        end
        for _, akar in ipairs({pathMurottal, pathPlugin}) do
            local f = File(akar)
            if f.exists() then sapu(f, akar, 1) end
        end
        table.sort(fs, function(a, b) return a.label:lower() < b.label:lower() end)
        for _, it in ipairs(fs) do arrNama[#arrNama + 1] = it.label; arrPath[#arrPath + 1] = it.path end
    end)
    return arrNama, arrPath
end

menuMemoriMurottal = function()
    local d; local s = ScrollView(ctxApp); local l = LinearLayout(ctxApp); l.setOrientation(1); l.setPadding(40,40,40,40); local navigasiAktif = false
    local function tutup(tujuan) if not navigasiAktif then navigasiAktif = true; pcall(function() d.dismiss() end); if tujuan then tugasTunda(150, tujuan) end end end

    btnLocal(l, "KEMBALI KE MENU UTAMA", function() tutup(tampilkanMenuUtama) end, "#D32F2F", "#FFFFFF")

    local nMur, pMur = dapatkanDaftarMurottal()
    local function judul(txt) local t = TextView(ctxApp); t.setText(txt); t.setTextColor(Color.BLUE); t.setPadding(0,30,0,10); l.addView(t) end

    judul("1. JADWAL SIARAN MUROTTAL (KHUSUS TIAP WAKTU)")
    local sp = {}
    local function buatSpinnerMurottal(teks, n)
        local tv = TextView(ctxApp); tv.setText(teks); tv.setTextColor(Color.BLACK); tv.setPadding(0,10,0,10); l.addView(tv)
        local spn = Spinner(ctxApp); spn.setAdapter(ArrayAdapter(ctxApp, android.R.layout.simple_list_item_1, jA(nMur))); spn.setPadding(0,0,0,20); l.addView(spn)
        local pos = 0; local m = cfg.memMurottal[n]
        for i, p in ipairs(pMur) do if m and m.path ~= "" and p == m.path then pos = i - 1; break end end
        spn.setSelection(pos)
        sp[n] = spn
    end
    for _, n in ipairs(_G.DaftarWaktuMemori) do buatSpinnerMurottal("Memori Murottal " .. n .. ":", n) end

    local function tg(txt, key) btnLocal(l, (cfg[key] and "[ ON ] " or "[ OFF ] ") .. txt, function() cfg[key] = not cfg[key]; simpanData(); tutup(menuMemoriMurottal) end, (cfg[key] and "#4CAF50" or "#9E9E9E"), "#FFFFFF") end

    judul("2. SAKELAR MUROTTAL 5 WAKTU")
    tg("Murottal Subuh", "murottal_subuh_on"); tg("Murottal Dzuhur", "murottal_dzuhur_on"); tg("Murottal Ashar", "murottal_ashar_on")
    tg("Murottal Maghrib", "murottal_maghrib_on"); tg("Murottal Isya", "murottal_isya_on")

    btnLocal(l, "SIMPAN SEMUA PENGATURAN MUROTTAL", function()
        for _, n in ipairs(_G.DaftarWaktuMemori) do
            local baru = pMur[sp[n].getSelectedItemPosition() + 1] or ""
            local lama = (cfg.memMurottal[n] and cfg.memMurottal[n].path) or ""
            if baru ~= lama then cfg.memMurottal[n] = {path = baru, pos = 0} end
        end
        simpanData(); infoVisual("Seluruh Pilihan Murottal Berhasil Disimpan."); tutup(tampilkanMenuUtama)
    end, "#2196F3", "#FFFFFF")

    btnLocal(l, "KEMBALI KE MENU UTAMA", function() tutup(tampilkanMenuUtama) end, "#D32F2F", "#FFFFFF")

    s.addView(l); d = AlertDialog.Builder(ctxApp).setTitle("Memori Murottal").setView(s).create()
    d.setOnCancelListener(DialogInterface.OnCancelListener{onCancel = function() tutup(tampilkanMenuUtama) end}); pcall(function() d.show() end)
end
-- ========================================================================

tampilkanMenuUtama = function()
    jalankanDiUILapor(function()
        lapor("3. Membuat isi menu...")
        local d; local s = ScrollView(ctxApp); local l = LinearLayout(ctxApp); l.setOrientation(1); l.setPadding(40,40,40,40); local navigasiAktif = false
        local function tutup(tujuan) if not navigasiAktif then navigasiAktif = true; pcall(function() d.dismiss() end); if tujuan then tugasTunda(150, tujuan) end; tugasTunda(800, function() navigasiAktif = false end) end end
        
        local pmSys = ctxApp.getSystemService(Context.POWER_SERVICE)
        if pmSys and not pmSys.isIgnoringBatteryOptimizations(ctxApp.getPackageName()) then
            local tP = TextView(ctxApp); tP.setTextColor(Color.parseColor("#F44336")); tP.setTextSize(15); tP.setText("PERINGATAN: Izin baterai dibatasi!"); l.addView(tP)
            btnLocal(l, "BUKA PENGATURAN BATERAI", function() tutup(bukaPengaturanBaterai) end, "#E91E63", "#FFFFFF")
        end
        
        local tH = TextView(ctxApp); tH.setTextColor(Color.BLACK); tH.setTextSize(16); tH.setPadding(0,10,0,30)
        tH.setText("LOKASI: " .. (cfg.lokasiDitemukan~="" and cfg.lokasiDitemukan or cfg.kota) .. "\n" .. formatTanggalIndo(os.date("%Y-%m-%d")) .. "\n\n" .. hitungSisaWaktuTeks()); l.addView(tH)
        
        local txtMaster = cfg.master_aktif and "[ ON ] MASTER SIARAN AKTIF" or "[ OFF ] MASTER SIARAN MATI"
        local clrMaster = cfg.master_aktif and "#4CAF50" or "#F44336"
        
        btnLocal(l, txtMaster, function() 
            cfg.master_aktif = not cfg.master_aktif; simpanData(); _G.SesiMesinAktif = _G.SesiMesinAktif + 1; tugasTunda(500, function() mesinWaktuMasjid(_G.SesiMesinAktif) end); 
            if not cfg.master_aktif then hentikanAudioDanSimpan() end
            bicaraGoogleTTS(cfg.master_aktif and "Sistem siaran master diaktifkan." or "Sistem siaran dimatikan secara total.", true)
            tutup(tampilkanMenuUtama) 
        end, clrMaster, "#FFFFFF")
        
        btnLocal(l, "PENGATURAN ADZAN & TARHIM", function() tutup(menuPengaturanAdzan) end, "#FF9800", "#FFFFFF")

        btnLocal(l, "MEMORI MUROTTAL (SUBUH - ISYA)", function() tutup(menuMemoriMurottal) end, "#795548", "#FFFFFF")
        
        btnLocal(l, "PENGATURAN LOKASI", function() tutup(menuPengaturanLokasi) end, "#009688", "#FFFFFF")

        btnLocal(l, cfg.lokasiOtomatis and "[ ON ] LOKASI OTOMATIS (IKUT POSISI HP)" or "[ OFF ] LOKASI OTOMATIS", function()
            cfg.lokasiOtomatis = not cfg.lokasiOtomatis; simpanData()
            if cfg.lokasiOtomatis then deteksiLokasiOtomatis(false) else bicaraGoogleTTS("Lokasi otomatis dimatikan.", true) end
            tutup(tampilkanMenuUtama)
        end, cfg.lokasiOtomatis and "#4CAF50" or "#9E9E9E", "#FFFFFF")
        
        btnLocal(l, "SELISIH WAKTU MANUAL", function() tutup(menuSelisihManual) end, "#673AB7", "#FFFFFF")
        
        btnLocal(l, "MENU FITUR LANJUTAN & INFO", function() tutup(menuFiturLanjutan) end, "#2196F3", "#FFFFFF")
        
        btnLocal(l, "RESTART SISTEM", function() 
            _G.SesiMesinAktif = _G.SesiMesinAktif + 1 
            _G.GembokAbsolut = {}; simpanGembok(); hentikanAudioDanSimpan(); 
            tugasTunda(1000, function() mesinWaktuMasjid(_G.SesiMesinAktif) end); 
            bicaraGoogleTTS("Sistem dimulai ulang.", true); tutup(tampilkanMenuUtama) 
        end, "#FF9800", "#FFFFFF")
        
        btnLocal(l, "RESET PABRIK (HAPUS DATA)", function()
            hentikanAudioDanSimpan()
            pcall(function() File(configFile).delete(); File(gembokFile).delete() end)
            _G.AdzanConfig = nil; _G.GembokAbsolut = {}; _G.BulanHijriyahIni = ""
            inisialisasiKonfigurasi(); cfg = _G.AdzanConfig; 
            _G.SesiMesinAktif = _G.SesiMesinAktif + 1; simpanData()
            tugasTunda(1000, function() mesinWaktuMasjid(_G.SesiMesinAktif) end)
            bicaraGoogleTTS("Sistem direset ke kondisi awal.", true)
            tutup(tampilkanMenuUtama)
        end, "#D32F2F", "#FFFFFF")
        
        btnLocal(l, "SEMBUNYIKAN APLIKASI (MESIN TETAP JALAN)", function() tutup(sembunyikanApp) end, "#9E9E9E", "#FFFFFF")
        btnLocal(l, "KELUAR TOTAL (MESIN BERHENTI)", function() keluarTotal() end, "#616161", "#FFFFFF")
        
        local tO = TextView(ctxApp); tO.setTextColor(Color.GRAY); tO.setTextSize(12); tO.setPadding(0,40,0,0)
        tO.setText("Sistem berjalan di latar belakang.\nTekan Sembunyikan untuk kembali ke layar awal."); l.addView(tO)

        -- Menu utama ditampilkan langsung di layar app (bukan dialog), supaya terlihat & terbaca di AndLua+
        s.addView(l)
        local wadah = LinearLayout(activity); wadah.setOrientation(1); wadah.setBackgroundColor(Color.WHITE)
        local tJudul = TextView(activity); tJudul.setText("Jadwal Salat by Reno"); tJudul.setTextSize(20)
        tJudul.setTextColor(Color.BLACK); tJudul.setPadding(40,60,40,20)
        wadah.addView(tJudul); wadah.addView(s)
        d = {dismiss = function() end, isShowing = function() return true end}
        local okS, eS = pcall(function() activity.setContentView(wadah) end)
        if not okS then tampilkanGalatLayar("setContentView: "..tostring(eS)) end
    end)
end

-- ===================== LOKASI OTOMATIS =====================
-- Mengikuti posisi HP: izin lokasi -> titik koordinat -> nama kota/kabupaten -> jadwal salat setempat
function punyaIzinLokasi()
    local ok, r = pcall(function()
        return activity.checkSelfPermission("android.permission.ACCESS_FINE_LOCATION") == 0
            or activity.checkSelfPermission("android.permission.ACCESS_COARSE_LOCATION") == 0
    end)
    return ok and r == true
end

function mintaIzinLokasi(setelah)
    if punyaIzinLokasi() then setelah(true); return end
    pcall(function()
        local arr = luajava.newArray(JString, 2)
        arr[0] = JString("android.permission.ACCESS_FINE_LOCATION")
        arr[1] = JString("android.permission.ACCESS_COARSE_LOCATION")
        activity.requestPermissions(arr, 7788)
    end)
    local percobaan = 0
    local function cek()
        percobaan = percobaan + 1
        if punyaIzinLokasi() then setelah(true)
        elseif percobaan >= 40 then setelah(false)
        else tugasTunda(1500, cek) end
    end
    tugasTunda(1500, cek)
end

-- cb(lat, lon) atau cb(nil) bila lokasi tidak didapat
function ambilTitikLokasi(cb)
    local lm = ctxApp.getSystemService(Context.LOCATION_SERVICE)
    local terbaik = nil
    for _, p in ipairs({"gps", "network", "passive"}) do
        local ok, loc = pcall(function() return lm.getLastKnownLocation(p) end)
        if ok and loc then
            if (not terbaik) or loc.getTime() > terbaik.getTime() then terbaik = loc end
        end
    end
    local selesai = false
    local listener = nil
    local function akhir(loc)
        if selesai then return end
        selesai = true
        if listener then pcall(function() lm.removeUpdates(listener) end) end
        if loc then
            local ok, lat, lon = pcall(function() return loc.getLatitude(), loc.getLongitude() end)
            if ok and lat then cb(lat, lon); return end
        end
        cb(nil)
    end
    -- titik terakhir yang masih baru (kurang dari 6 jam) langsung dipakai
    if terbaik and (os.time() * 1000 - terbaik.getTime()) < 6 * 3600 * 1000 then akhir(terbaik); return end

    listener = luajava.createProxy("android.location.LocationListener", {
        onLocationChanged = function(l)
            local ok, lat = pcall(function() return l.getLatitude() end)
            if ok and lat then akhir(l) end
        end,
        onStatusChanged = function(p, s, e) end,
        onProviderEnabled = function(p) end,
        onProviderDisabled = function(p) end,
    })
    local dipakai = false
    for _, p in ipairs({"network"}) do
        pcall(function()
            if lm.isProviderEnabled(p) then
                lm.requestSingleUpdate(p, listener, Looper.getMainLooper()); dipakai = true
            end
        end)
    end
    if not dipakai then akhir(terbaik); return end
    tugasTunda(25000, function() akhir(terbaik) end)
end

function bersihNamaWilayah(n)
    n = tostring(n or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local rendah = n:lower()
    local awalan = {"kota administrasi ", "kabupaten administrasi ", "kabupaten ", "kota ", "kab. ", "kab "}
    for _, a in ipairs(awalan) do
        if rendah:sub(1, #a) == a then return n:sub(#a + 1) end
    end
    local akhiran = {" regency", " administrative city", " city"}
    for _, a in ipairs(akhiran) do
        if #rendah > #a and rendah:sub(-#a) == a then return n:sub(1, #n - #a) end
    end
    return n
end

function buatDaftarKandidat()
    local kand, sudah = {}, {}
    local function tambah(n)
        n = bersihNamaWilayah(n)
        if n == "" then return end
        local k = n:lower()
        if sudah[k] then return end
        sudah[k] = true; kand[#kand + 1] = n
        if k:find("jakarta") and not sudah["jakarta"] then sudah["jakarta"] = true; kand[#kand + 1] = "Jakarta" end
    end
    return kand, tambah
end

-- tahap 1: lewat internet (tanpa layanan Google)
function namaWilayahOnline(lat, lon, cb)
    local kand, tambah = buatDaftarKandidat()
    local url = string.format("https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=%.5f&longitude=%.5f&localityLanguage=id", lat, lon)
    getAPI(url, function(s, res)
        if s then
            pcall(function()
                local d = JSONObject(res)
                local lv5, lv6 = {}, {}
                local info = d.optJSONObject("localityInfo")
                local arr = info and info.optJSONArray("administrative")
                if arr then
                    for i = 0, arr.length() - 1 do
                        local o = arr.getJSONObject(i)
                        local lv = o.optInt("adminLevel", 0); local nm = o.optString("name", "")
                        if lv == 5 then lv5[#lv5 + 1] = nm elseif lv == 6 then lv6[#lv6 + 1] = nm end
                    end
                end
                for _, n in ipairs(lv5) do tambah(n) end
                tambah(d.optString("city", ""))
                for _, n in ipairs(lv6) do tambah(n) end
                tambah(d.optString("locality", ""))
            end)
        end
        cb(kand)
    end)
end

-- tahap 2 (cadangan): Geocoder bawaan HP
function namaWilayahGeocoder(lat, lon)
    local kand, tambah = buatDaftarKandidat()
    pcall(function()
        local Geocoder = luajava.bindClass("android.location.Geocoder")
        if Geocoder.isPresent() then
            local g = Geocoder(ctxApp, Locale("id", "ID"))
            local daftar = g.getFromLocation(lat, lon, 1)
            if daftar and daftar.size() > 0 then
                local a = daftar.get(0)
                tambah(a.getSubAdminArea()); tambah(a.getLocality()); tambah(a.getSubLocality())
            end
        end
    end)
    return kand
end

-- lokasi disimpan di storage; cek ulang hanya bila sudah 30 hari sejak pengecekan terakhir
local JEDA_CEK_LOKASI = 30 * 24 * 3600
function lokasiPerluDicek()
    local terakhir = tonumber(cfg.lokasiCekTerakhir) or 0
    return cfg.kota == "Belum Diatur" or (os.time() - terakhir) >= JEDA_CEK_LOKASI
end

function deteksiLokasiOtomatis(senyap)
    if _G.SedangDeteksiLokasi then return end
    if senyap and not punyaIzinLokasi() then return end
    _G.SedangDeteksiLokasi = true
    local function selesai() _G.SedangDeteksiLokasi = false end
    local function gagal(pesan) selesai(); if not senyap then bicaraGoogleTTS(pesan, false) end end
    local lokasiLama = cfg.lokasiDitemukan

    mintaIzinLokasi(function(ada)
        if not ada then gagal("Izin lokasi ditolak. Silakan pilih kota secara manual di menu Pengaturan Lokasi."); return end
        if not senyap then bicaraGoogleTTS("Mendeteksi lokasi.", true) end
        ambilTitikLokasi(function(lat, lon)
            if not lat then gagal("Lokasi belum terdeteksi. Nyalakan lokasi di HP, atau pilih kota secara manual."); return end

            local function coba(daftar, i, tahap)
                if i > #daftar then
                    if tahap == 1 then coba(namaWilayahGeocoder(lat, lon), 1, 2); return end
                    gagal("Nama wilayah belum cocok dengan data jadwal. Silakan pilih kota secara manual.")
                    return
                end
                local nama = daftar[i]
                sinkronisasiJadwalV3Cerdas(nama, function(s, hasil)
                    if s then
                        cfg.kota = nama; cfg.lokasiOtomatis = true; cfg.lokasiCekTerakhir = os.time(); simpanData(); selesai()
                        if (not senyap) or hasil ~= lokasiLama then
                            bicaraGoogleTTS("Lokasi terdeteksi, " .. tostring(hasil) .. ". Jadwal salat sudah disesuaikan.", true)
                            jalankanDiUI(function() pcall(tampilkanMenuUtama) end)
                        end
                    else
                        coba(daftar, i + 1, tahap)
                    end
                end, true)
            end
            namaWilayahOnline(lat, lon, function(kand) coba(kand, 1, 1) end)
        end)
    end)
end

-- cek ulang tiap 30 menit (diam-diam, hanya bicara bila wilayah berubah)
if not _G.LokasiLoopAktif then
    _G.LokasiLoopAktif = true
    local function putar()
        tugasTunda(3600000, function()
            if cfg.lokasiOtomatis and lokasiPerluDicek() then pcall(function() deteksiLokasiOtomatis(true) end) end
            putar()
        end)
    end
    putar()
end
-- ============================================================

tugasTunda(1000, function() mesinWaktuMasjid(_G.SesiMesinAktif) end)
tugasTunda(2500, function() if cfg.lokasiOtomatis and lokasiPerluDicek() then pcall(function() deteksiLokasiOtomatis(cfg.kota ~= "Belum Diatur") end) end end)

if not _G.SapaAwalV50 then 
    _G.SapaAwalV50 = true
    ambilTanggalHijriyah(0, function(h, t, bln) _G.BulanHijriyahIni = bln or "" end)
end
pcall(function()
    local tvMuat = TextView(activity); tvMuat.setText("Jadwal Salat by Reno\n1. Memuat menu..."); tvMuat.setTextSize(18)
    tvMuat.setTextColor(Color.BLACK); tvMuat.setPadding(40,160,40,40); activity.setContentView(tvMuat); _G.tvMuat = tvMuat
end)
local okT, eT = pcall(function()
    Handler(Looper.getMainLooper()).postDelayed(Runnable{run=function()
        lapor("2. Timer jalan, memanggil menu...")
        local ok2, e2 = pcall(function() tampilkanMenuUtama() end)
        if not ok2 then tampilkanGalatLayar("panggil menu: "..tostring(e2)) end
    end}, 400)
end)
if not okT then tampilkanGalatLayar("timer: "..tostring(eT)) end
