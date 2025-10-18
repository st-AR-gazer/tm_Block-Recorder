namespace TMBR_Core {

class JsonSink {
    string relPath;
    string metaStr;
    array<string> evs;

    JsonSink(const string &in relativePath) {
        relPath = relativePath;
        BuildMeta();
    }

    void BuildMeta() {
        Json::Value@ meta = Json::Object();
        meta["createdUtc"] = Time::FormatStringUTC("%Y-%m-%dT%H:%M:%SZ");
        auto app = GetApp();
        auto edFree = app is null ? null : cast<CGameCtnEditorFree>(app.Editor);
        auto ch = edFree is null ? null : edFree.Challenge;
        if (ch !is null) {
            auto mi = ch.MapInfo;
            meta["mapName"]    = string(ch.MapName);
            meta["collection"] = string(ch.CollectionName);
            meta["author"]     = string(ch.AuthorNickName);
            meta["mapUid"]     = (mi is null ? "" : string(mi.MapUid));
        } else {
            meta["mapName"]    = "";
            meta["collection"] = "";
            meta["author"]     = "";
            meta["mapUid"]     = "";
        }
        metaStr = Json::Write(meta, false);
    }

    void AppendEvent(Json::Value@ ev, bool flushEach) {
        string s = Json::Write(ev, false);
        evs.InsertLast(s);
        if (flushEach) Flush(false);
    }

    void Flush(bool pretty = false) {
        string abs = IO::FromStorageFolder(relPath);
        int iF = abs.LastIndexOf("/");
        int iB = abs.LastIndexOf("\\");
        int i  = Math::Max(iF, iB);
        string folder = i >= 0 ? abs.SubStr(0, i) : "";
        if (folder.Length > 0 && !IO::FolderExists(folder)) {
            IO::CreateFolder(folder);
        }

        IO::File f(abs, IO::FileMode::Write);
        f.Write("{\"meta\":");
        f.Write(metaStr);
        f.Write(",\"events\":[");
        if (pretty && evs.Length > 0) f.Write("\n");

        uint written = 0;
        for (uint k = 0; k < evs.Length; k++) {
            if (k > 0) {
                f.Write(",");
                if (pretty) f.Write("\n");
            }
            if (pretty) f.Write("  ");
            f.Write(evs[k]);
            written++;
            if ((written % 200) == 0) {
                f.Flush();
                yield();
            }
        }

        if (pretty && evs.Length > 0) f.Write("\n");
        f.Write("]}");
        f.Close();
    }
}

}
