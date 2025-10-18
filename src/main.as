[Setting category="TM Block Recorder" name="Auto start on map enter"]
bool S_AutoStartOnMapEnter = true;

[Setting category="TM Block Recorder" name="Flush every event"]
bool S_FlushEveryEvent = true;

[Setting category="TM Block Recorder" name="Dir offset (advanced)"]
uint16 S_DirOffset = 0x6C;

[Setting category="TM Block Recorder" name="Global file name (blank = per-map, click Apply)"]
string S_GlobalFileName = "";

[Setting category="TM Block Recorder" name="Autosave interval (seconds, 0 = off)"]
int S_AutoSaveSec = 30;

[Setting category="TM Block Recorder" name="Full rescan interval (seconds, 0 = off)"]
int S_FullScanSec = 15;

[Setting category="TM Block Recorder" name="Backfill existing on start"]
bool S_BackfillOnStart = true;

string g_LastRelPath = "";
string g_SessionStamp = "";
int64 g_LastAutoSaveStamp = 0;
string g_GlobalNameCommitted = "";
bool g_ShowUI = true;

bool g_PendingFlush = false;
bool g_PendingStopAndFlush = false;
bool g_PendingBackfill = false;

string SanitizeFileName(const string &in s) {
    const string invalid = "<>:\"/\\|?*";
    string r = "";
    int len = s.Length;
    for (int i = 0; i < len; i++) {
        string ch = s.SubStr(i, 1);
        int c = int(s[i]);
        if (c <= 31) { r += "_"; continue; }
        if (invalid.IndexOf(ch) >= 0) { r += "_"; continue; }
        if (ch == " ") { r += "_"; continue; }
        r += ch;
    }
    if (r.Length == 0) r = "unnamed";
    return r;
}

string TrimSpaces(const string &in s) {
    int len = s.Length;
    int start = 0;
    while (start < len) {
        string ch = s.SubStr(start, 1);
        if (ch == " " || ch == "\t") start++;
        else break;
    }
    int end = len - 1;
    while (end >= start) {
        string ch = s.SubStr(end, 1);
        if (ch == " " || ch == "\t") end--;
        else break;
    }
    if (start == 0 && end == len - 1) return s;
    if (end < start) return "";
    return s.SubStr(start, end - start + 1);
}

bool EndsWithJson(const string &in name) {
    int n = name.Length;
    if (n < 5) return false;
    return name.SubStr(n - 5, 5) == ".json";
}

string EnsureJsonExt(const string &in name) {
    if (EndsWithJson(name)) return name;
    return name + ".json";
}

string GetOrMakeSessionStamp() {
    if (g_SessionStamp.Length == 0) {
        g_SessionStamp = Time::FormatStringUTC("%Y-%m-%dT%H-%M-%SZ");
    }
    return g_SessionStamp;
}

string GetMapUidFromMapInfo(CGameCtnChallenge@ ch) {
    if (ch is null) return "";
    auto mi = ch.MapInfo;
    string uid = (mi is null) ? "" : string(mi.MapUid);
    if (uid.Length == 0) uid = "session-" + GetOrMakeSessionStamp();
    return uid;
}

string BuildPerMapRelPath() {
    auto app = GetApp();
    auto edFree = app is null ? null : cast<CGameCtnEditorFree>(app.Editor);
    auto ch = edFree is null ? null : edFree.Challenge;
    if (ch is null) return "placements/" + ("session-" + GetOrMakeSessionStamp()) + ".unspecified.json";
    string uid  = GetMapUidFromMapInfo(ch);
    string name = string(ch.MapName);
    string safeName = SanitizeFileName(name);
    return "placements/" + uid + "." + safeName + ".json";
}

string BuildSingleRelPathFromCommitted() {
    string trimmed = TrimSpaces(g_GlobalNameCommitted);
    string fname = SanitizeFileName(trimmed);
    if (fname.Length == 0) fname = "all_placements";
    fname = EnsureJsonExt(fname);
    return "placements/" + fname;
}

bool IsGlobalModeCommitted() {
    return TrimSpaces(g_GlobalNameCommitted).Length > 0;
}

string DesiredRelPath(bool inEditor) {
    if (IsGlobalModeCommitted()) return BuildSingleRelPathFromCommitted();
    if (inEditor) return BuildPerMapRelPath();
    return "placements/" + ("session-" + GetOrMakeSessionStamp()) + ".unspecified.json";
}

void Main() {
    TMBR_Core::InitOffsets(S_DirOffset);
    g_GlobalNameCommitted = TrimSpaces(S_GlobalFileName);
    while (true) {
        auto app = GetApp();
        bool inEditor = app !is null && app.Editor !is null && cast<CGameCtnEditorFree>(app.Editor) !is null;
        string desired = DesiredRelPath(inEditor);

        if (S_AutoStartOnMapEnter && inEditor && !TMBR_Core::Recorder_IsActive()) {
            TMBR_Core::Recorder_Start(desired);
            g_LastRelPath = desired;
            g_LastAutoSaveStamp = int64(Time::Stamp);
            log("[TMBR] Started at: " + desired, LogLevel::Info, 134, "Main");
            if (S_BackfillOnStart) {
                TMBR_Core::Recorder_BackfillExisting(false);
                log("[TMBR] Backfilled existing placements", LogLevel::Info, 137, "Main");
            }
        }

        if (TMBR_Core::Recorder_IsActive() && desired != g_LastRelPath && desired.Length > 0) {
            log("[TMBR] Rotating output:\n - old: " + g_LastRelPath + "\n - new: " + desired, LogLevel::Info, 142, "Main");
            TMBR_Core::Recorder_StopAndFlush();
            TMBR_Core::Recorder_Start(desired);
            g_LastRelPath = desired;
            g_LastAutoSaveStamp = int64(Time::Stamp);
            if (S_BackfillOnStart) {
                TMBR_Core::Recorder_BackfillExisting(false);
                log("[TMBR] Backfilled existing placements after rotation", LogLevel::Info, 149, "Main");
            }
        }

        if (!inEditor && TMBR_Core::Recorder_IsActive()) {
            log("[TMBR] Editor closed; flushing: " + g_LastRelPath, LogLevel::Info, 154, "Main");
            TMBR_Core::Recorder_StopAndFlush();
            g_LastRelPath = "";
            g_SessionStamp = "";
            g_LastAutoSaveStamp = 0;
        }

        if (TMBR_Core::Recorder_IsActive()) {
            TMBR_Core::Recorder_Update(S_FlushEveryEvent, S_FullScanSec);
            if (S_AutoSaveSec > 0) {
                int64 now = int64(Time::Stamp);
                if (now - g_LastAutoSaveStamp >= int64(S_AutoSaveSec)) {
                    TMBR_Core::Recorder_Flush(false);
                    g_LastAutoSaveStamp = now;
                }
            }
        }

        if (g_PendingBackfill) {
            if (TMBR_Core::Recorder_IsActive()) {
                TMBR_Core::Recorder_BackfillExisting(false);
                log("[TMBR] Backfilled existing placements (manual)", LogLevel::Info, 175, "Main");
            }
            g_PendingBackfill = false;
        }

        if (g_PendingFlush) {
            if (TMBR_Core::Recorder_IsActive()) {
                TMBR_Core::Recorder_Flush(false);
                g_LastAutoSaveStamp = int64(Time::Stamp);
            }
            g_PendingFlush = false;
        }

        if (g_PendingStopAndFlush) {
            if (TMBR_Core::Recorder_IsActive()) {
                TMBR_Core::Recorder_StopAndFlush();
            }
            g_LastRelPath = "";
            g_SessionStamp = "";
            g_LastAutoSaveStamp = 0;
            g_PendingStopAndFlush = false;
        }

        yield();
    }
}

void RenderMenu() {
    if (UI::MenuItem("\\$39fTM Block Recorder")) {
        g_ShowUI = true;
    }
}

void RenderInterface() {
    if (!g_ShowUI) return;
    auto app = GetApp();
    bool inEditor = app !is null && app.Editor !is null && cast<CGameCtnEditorFree>(app.Editor) !is null;
    string desired = DesiredRelPath(inEditor);
    bool open = g_ShowUI;
    if (UI::Begin("TM Block Recorder", open, UI::WindowFlags::AlwaysAutoResize)) {
        UI::Text("Status: " + (TMBR_Core::Recorder_IsActive() ? "\\$0b0Recording" : "\\$b00Stopped"));
        UI::Text("Events: " + TMBR_Core::Recorder_EventCount());

        auto edFree = app is null ? null : cast<CGameCtnEditorFree>(app.Editor);
        auto ch = edFree is null ? null : edFree.Challenge;
        if (ch !is null) {
            UI::Separator();
            UI::Text("Blocks: " + ch.Blocks.Length);
            UI::Text("Items:  " + ch.AnchoredObjects.Length);
            auto mi = ch.MapInfo;
            UI::Text("Map: " + string(ch.MapName));
            UI::Text("UID: " + (mi is null ? "" : string(mi.MapUid)));
        }

        UI::Separator();
        string tmpName = S_GlobalFileName;
        tmpName = UI::InputText("Global file name (blank = per-map)", tmpName);
        if (tmpName != S_GlobalFileName) S_GlobalFileName = tmpName;
        UI::SameLine();
        string stagedTrim = TrimSpaces(S_GlobalFileName);
        string committedTrim = TrimSpaces(g_GlobalNameCommitted);
        bool needsApply = stagedTrim != committedTrim;
        if (UI::Button("Apply")) {
            g_GlobalNameCommitted = stagedTrim;
            log("[TMBR] Global name applied: '" + g_GlobalNameCommitted + "'", LogLevel::Info, 239, "RenderInterface");
        }
        if (!needsApply) {
            UI::SameLine();
            UI::TextDisabled("(no change)");
        }

        UI::Separator();
        if (IsGlobalModeCommitted()) {
            UI::Text("Mode: Single file");
            UI::Text("Applied name: " + g_GlobalNameCommitted);
        } else {
            UI::Text("Mode: Per-map files");
        }

        int tmpSecs = S_AutoSaveSec;
        tmpSecs = UI::InputInt("Autosave interval (s; 0=off)", tmpSecs);
        if (tmpSecs < 0) tmpSecs = 0;
        if (tmpSecs != S_AutoSaveSec) S_AutoSaveSec = tmpSecs;

        int tmpScan = S_FullScanSec;
        tmpScan = UI::InputInt("Full rescan interval (s; 0=off)", tmpScan);
        if (tmpScan < 0) tmpScan = 0;
        if (tmpScan != S_FullScanSec) S_FullScanSec = tmpScan;

        bool tmpStartOnEnter = S_AutoStartOnMapEnter;
        tmpStartOnEnter = UI::Checkbox("Auto start on map enter", tmpStartOnEnter);
        if (tmpStartOnEnter != S_AutoStartOnMapEnter) S_AutoStartOnMapEnter = tmpStartOnEnter;

        bool tmpBackfill = S_BackfillOnStart;
        tmpBackfill = UI::Checkbox("Backfill existing on start", tmpBackfill);
        if (tmpBackfill != S_BackfillOnStart) S_BackfillOnStart = tmpBackfill;

        UI::Separator();
        UI::Text("Current output (relative to Storage):");
        UI::TextWrapped((TMBR_Core::Recorder_IsActive() && g_LastRelPath.Length > 0) ? g_LastRelPath : desired);

        UI::Separator();
        if (TMBR_Core::Recorder_IsActive()) {
            if (UI::Button("Flush Now")) {
                g_PendingFlush = true;
            }
            UI::SameLine();
            if (UI::Button("Backfill existing now")) {
                g_PendingBackfill = true;
            }
            UI::SameLine();
            if (UI::Button("Stop & Flush")) {
                g_PendingStopAndFlush = true;
            }
        } else {
            if (UI::Button("Start")) {
                TMBR_Core::Recorder_Start(desired);
                g_LastRelPath = desired;
                g_LastAutoSaveStamp = int64(Time::Stamp);
                log("[TMBR] Start via UI at: " + desired, LogLevel::Info, 294, "RenderInterface");
                if (S_BackfillOnStart) {
                    g_PendingBackfill = true;
                }
            }
        }
    }
    UI::End();
    g_ShowUI = open;
}
