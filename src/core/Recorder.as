namespace TMBR_Core {

class BlockSnap {
    uint uid;
    bool hasUid;
    string key;
    string name;
    uint descId;
    bool isGhost;
    bool isGround;
    bool isFree;
    int dir;
    nat3 coord;
    vec3 pos;
    vec3 rot;
}

class ItemSnap {
    CGameCtnAnchoredObject@ ref;
    string name;
    uint modelId;
    vec3 pos;
    vec3 rot;
}

class Recorder {
    JsonSink@ sink;

    uint lastBlocks = 0;
    uint lastItems  = 0;

    int64 lastFullScanStamp = 0;

    dictionary prevBlocks;
    array<CGameCtnAnchoredObject@> prevItemHandles;
    array<ItemSnap@> prevItemSnaps;

    bool backfilled = false;

    uint64 seq = 0;
    uint total = 0;

    Recorder(JsonSink@ s) { @sink = s; SeedSnapshots(); }

    void SeedSnapshots() {
        lastBlocks = 0;
        lastItems = 0;
        prevBlocks = dictionary();
        if (prevItemHandles.Length > 0) prevItemHandles.RemoveRange(0, prevItemHandles.Length);
        if (prevItemSnaps.Length > 0) prevItemSnaps.RemoveRange(0, prevItemSnaps.Length);

        auto app = GetApp();
        auto edFree = app is null ? null : cast<CGameCtnEditorFree>(app.Editor);
        auto ch = edFree is null ? null : edFree.Challenge;
        if (ch is null) return;

        lastBlocks = ch.Blocks.Length;
        for (uint i = 0; i < ch.Blocks.Length; i++) {
            auto @b = ch.Blocks[i];
            BlockSnap@ bs = MakeBlockSnap(b);
            prevBlocks.Set(bs.key, @bs);
        }

        lastItems = ch.AnchoredObjects.Length;
        for (uint i = 0; i < ch.AnchoredObjects.Length; i++) {
            auto @it = ch.AnchoredObjects[i];
            ItemSnap@ snap = MakeItemSnap(it);
            prevItemHandles.InsertLast(it);
            prevItemSnaps.InsertLast(snap);
        }

        lastFullScanStamp = int64(Time::Stamp);
    }

    string BlockKey(BlockSnap@ bs) {
        if (bs.hasUid) return "B#" + Helpers::ToHex8(bs.uid);
        return "B@" + Helpers::ToHex8(bs.descId) + "|" + bs.isGhost + "|" + bs.isGround + "|" + bs.isFree + "|"
             + bs.coord.x + "," + bs.coord.y + "," + bs.coord.z + "|" + bs.dir;
    }

    bool NearlyEq(float a, float b, float eps) { return Math::Abs(a - b) <= eps; }
    bool VecNearlyEq(const vec3 &in a, const vec3 &in b, float eps) {
        return NearlyEq(a.x,b.x,eps) && NearlyEq(a.y,b.y,eps) && NearlyEq(a.z,b.z,eps);
    }

    BlockSnap@ MakeBlockSnap(CGameCtnBlock@ b) {
        BlockSnap@ s = BlockSnap();
        s.uid      = Helpers::GetBlockUniqueID(b);
        s.hasUid   = (s.uid != 0);
        s.name     = Helpers::GetBlockName(b);
        s.descId   = b.DescId.Value;
        s.isGhost  = b.IsGhostBlock();
        s.isGround = b.IsGround;
        s.isFree   = Helpers::IsBlockFree(b);
        s.dir      = int(b.Dir);
        s.coord    = Helpers::GetBlockCoord(b);
        s.pos      = Helpers::GetBlockLocation(b);
        s.rot      = Helpers::GetBlockRotation(b);
        s.key      = BlockKey(s);
        return s;
    }

    ItemSnap@ MakeItemSnap(CGameCtnAnchoredObject@ it) {
        ItemSnap@ s = ItemSnap();
        @s.ref   = it;
        s.name   = Helpers::GetItemName(it);
        s.modelId= it.ItemModel is null ? 0 : it.ItemModel.Id.Value;
        s.pos    = Helpers::GetItemLocation(it);
        s.rot    = Helpers::GetItemRotation(it);
        return s;
    }

    Json::Value@ Vec3ToJson(const vec3 &in v) {
        Json::Value@ arr = Json::Array();
        Json::Value@ vx = Json::Value(v.x); arr.Add(vx);
        Json::Value@ vy = Json::Value(v.y); arr.Add(vy);
        Json::Value@ vz = Json::Value(v.z); arr.Add(vz);
        return arr;
    }

    Json::Value@ Nat3ToJson(const nat3 &in n) {
        Json::Value@ arr = Json::Array();
        Json::Value@ vx = Json::Value(float(n.x)); arr.Add(vx);
        Json::Value@ vy = Json::Value(float(n.y)); arr.Add(vy);
        Json::Value@ vz = Json::Value(float(n.z)); arr.Add(vz);
        return arr;
    }

    uint EventCount() const { return total; }

    void Update(bool flushEach, int fullScanSec) {
        auto app = GetApp();
        auto edFree = app is null ? null : cast<CGameCtnEditorFree>(app.Editor);
        auto ch = edFree is null ? null : edFree.Challenge;
        if (ch is null) return;

        uint nb = ch.Blocks.Length;
        if (nb > lastBlocks) {
            for (uint i = lastBlocks; i < nb; i++) {
                auto @b = ch.Blocks[i];
                RecordBlockAdded(b, i, flushEach);
                BlockSnap@ bs = MakeBlockSnap(b);
                prevBlocks.Set(bs.key, @bs);
            }
        }
        lastBlocks = nb;

        uint ni = ch.AnchoredObjects.Length;
        if (ni > lastItems) {
            for (uint i = lastItems; i < ni; i++) {
                auto @it = ch.AnchoredObjects[i];
                RecordItemAdded(it, i, flushEach);
                ItemSnap@ itemSnap = MakeItemSnap(it);
                prevItemHandles.InsertLast(it);
                prevItemSnaps.InsertLast(itemSnap);
            }
        }
        lastItems = ni;

        if (fullScanSec > 0) {
            int64 now = int64(Time::Stamp);
            if (now - lastFullScanStamp >= int64(fullScanSec)) {
                FullScan(ch, flushEach);
                lastFullScanStamp = now;
            }
        }
    }

    void FullScan(CGameCtnChallenge@ ch, bool flushEach) {
        dictionary curr;
        for (uint i = 0; i < ch.Blocks.Length; i++) {
            BlockSnap@ bs = MakeBlockSnap(ch.Blocks[i]);
            curr.Set(bs.key, @bs);
            if ((i % 1000) == 0) yield();
        }

        array<string>@ keys = prevBlocks.GetKeys();
        if (keys !is null) {
            for (uint i = 0; i < keys.Length; i++) {
                string k = keys[i];
                BlockSnap@ oldS;
                prevBlocks.Get(k, @oldS);
                if (oldS is null) continue;

                BlockSnap@ newS;
                bool existsNow = curr.Get(k, @newS);
                if (!existsNow || newS is null) {
                    RecordBlockRemoved(oldS, flushEach);
                    continue;
                }

                bool changed = false;
                if (oldS.isFree || newS.isFree) {
                    if (!VecNearlyEq(oldS.pos, newS.pos, 0.0001f) || !VecNearlyEq(oldS.rot, newS.rot, 0.0001f)) changed = true;
                } else {
                    if (oldS.dir != newS.dir) changed = true;
                    if (oldS.coord.x != newS.coord.x || oldS.coord.y != newS.coord.y || oldS.coord.z != newS.coord.z) changed = true;
                }
                if (changed) RecordBlockUpdated(oldS, newS, flushEach);
                if ((i % 1000) == 0) yield();
            }
        }

        prevBlocks = curr;

        array<CGameCtnAnchoredObject@> currHandles;
        array<ItemSnap@> currSnaps;
        for (uint i = 0; i < ch.AnchoredObjects.Length; i++) {
            auto @it = ch.AnchoredObjects[i];
            currHandles.InsertLast(it);
            currSnaps.InsertLast(MakeItemSnap(it));
            if ((i % 1000) == 0) yield();
        }

        for (uint i = 0; i < prevItemHandles.Length; i++) {
            auto @prevH = prevItemHandles[i];
            auto @prevS = prevItemSnaps[i];
            bool found = false;
            uint foundIx = 0;
            for (uint j = 0; j < currHandles.Length; j++) {
                if (prevH is currHandles[j]) { found = true; foundIx = j; break; }
            }
            if (!found) {
                RecordItemRemoved(prevS, flushEach);
            } else {
                auto @newS = currSnaps[foundIx];
                if (!VecNearlyEq(prevS.pos, newS.pos, 0.0001f) || !VecNearlyEq(prevS.rot, newS.rot, 0.0001f)) {
                    RecordItemUpdated(prevS, newS, flushEach);
                }
            }
            if ((i % 1000) == 0) yield();
        }

        prevItemHandles = currHandles;
        prevItemSnaps = currSnaps;
    }

    void BackfillExisting(bool flushEachIgnored) {
        if (backfilled) return;

        auto app = GetApp();
        auto edFree = app is null ? null : cast<CGameCtnEditorFree>(app.Editor);
        auto ch = edFree is null ? null : edFree.Challenge;
        if (ch is null) return;

        const uint batchYield = 500;
        for (uint i = 0; i < ch.Blocks.Length; i++) {
            RecordBlockExisting(ch.Blocks[i], i, false);
            if ((i % batchYield) == 0) yield();
        }
        for (uint i = 0; i < ch.AnchoredObjects.Length; i++) {
            RecordItemExisting(ch.AnchoredObjects[i], i, false);
            if ((i % batchYield) == 0) yield();
        }

        sink.Flush(false);
        backfilled = true;
    }

    void RecordBlockAdded(CGameCtnBlock@ b, uint index, bool flushEach) {
        auto when = Helpers::NowIso8601Utc();
        auto pos  = Helpers::GetBlockLocation(b);
        auto rot  = Helpers::GetBlockRotation(b);
        auto crd  = Helpers::GetBlockCoord(b);
        int  dirI = int(b.Dir);

        Json::Value@ ev = Json::Object();
        ev["type"]       = "block_added";
        ev["timestamp"]  = when;
        ev["seq"]        = int(seq++);
        ev["index"]      = int(index);

        Json::Value@ idv = Json::Object();
        idv["name"]     = Helpers::GetBlockName(b);
        idv["descId"]   = Helpers::ToHex8(b.DescId.Value);
        idv["isGhost"]  = b.IsGhostBlock();
        idv["isGround"] = b.IsGround;
        idv["isFree"]   = Helpers::IsBlockFree(b);
        idv["uid"]      = int(Helpers::GetBlockUniqueID(b));
        ev["id"] = idv;

        ev["position"] = Vec3ToJson(pos);
        ev["rotation"] = Vec3ToJson(rot);
        ev["coord"]    = Nat3ToJson(crd);

        Json::Value@ jdir = Json::Object();
        jdir["enum"] = dirI;
        jdir["name"] = Helpers::DirToString(dirI);
        ev["direction"] = jdir;

        sink.AppendEvent(ev, flushEach);
        total++;
    }

    void RecordBlockExisting(CGameCtnBlock@ b, uint index, bool flushEach) {
        auto pos  = Helpers::GetBlockLocation(b);
        auto rot  = Helpers::GetBlockRotation(b);
        auto crd  = Helpers::GetBlockCoord(b);
        int  dirI = int(b.Dir);

        Json::Value@ ev = Json::Object();
        ev["type"]              = "block_existing";
        ev["timestamp"]         = Helpers::NowIso8601Utc();
        ev["placementUnknown"]  = true;
        ev["seq"]               = int(seq++);
        ev["index"]             = int(index);

        Json::Value@ idv = Json::Object();
        idv["name"]     = Helpers::GetBlockName(b);
        idv["descId"]   = Helpers::ToHex8(b.DescId.Value);
        idv["isGhost"]  = b.IsGhostBlock();
        idv["isGround"] = b.IsGround;
        idv["isFree"]   = Helpers::IsBlockFree(b);
        idv["uid"]      = int(Helpers::GetBlockUniqueID(b));
        ev["id"] = idv;

        ev["position"] = Vec3ToJson(pos);
        ev["rotation"] = Vec3ToJson(rot);
        ev["coord"]    = Nat3ToJson(crd);

        Json::Value@ jdir = Json::Object();
        jdir["enum"] = dirI;
        jdir["name"] = Helpers::DirToString(dirI);
        ev["direction"] = jdir;

        sink.AppendEvent(ev, false);
        total++;
    }

    void RecordBlockRemoved(BlockSnap@ oldS, bool flushEach) {
        Json::Value@ ev = Json::Object();
        ev["type"]       = "block_removed";
        ev["timestamp"]  = Helpers::NowIso8601Utc();
        ev["seq"]        = int(seq++);

        Json::Value@ idv = Json::Object();
        idv["name"]     = oldS.name;
        idv["descId"]   = Helpers::ToHex8(oldS.descId);
        idv["isGhost"]  = oldS.isGhost;
        idv["isGround"] = oldS.isGround;
        idv["isFree"]   = oldS.isFree;
        idv["uid"]      = int(oldS.uid);
        ev["id"] = idv;

        Json::Value@ last = Json::Object();
        last["position"] = Vec3ToJson(oldS.pos);
        last["rotation"] = Vec3ToJson(oldS.rot);
        last["coord"]    = Nat3ToJson(oldS.coord);

        Json::Value@ jdir = Json::Object();
        jdir["enum"] = oldS.dir;
        jdir["name"] = Helpers::DirToString(oldS.dir);
        last["direction"] = jdir;

        ev["last"] = last;

        sink.AppendEvent(ev, flushEach);
        total++;
    }

    void RecordBlockUpdated(BlockSnap@ beforeS, BlockSnap@ afterS, bool flushEach) {
        Json::Value@ ev = Json::Object();
        ev["type"]       = "block_updated";
        ev["timestamp"]  = Helpers::NowIso8601Utc();
        ev["seq"]        = int(seq++);

        Json::Value@ idv = Json::Object();
        idv["name"]     = afterS.name;
        idv["descId"]   = Helpers::ToHex8(afterS.descId);
        idv["isGhost"]  = afterS.isGhost;
        idv["isGround"] = afterS.isGround;
        idv["isFree"]   = afterS.isFree;
        idv["uid"]      = int(afterS.uid);
        ev["id"] = idv;

        Json::Value@ before = Json::Object();
        before["position"] = Vec3ToJson(beforeS.pos);
        before["rotation"] = Vec3ToJson(beforeS.rot);
        before["coord"]    = Nat3ToJson(beforeS.coord);
        Json::Value@ bdir = Json::Object();
        bdir["enum"] = beforeS.dir;
        bdir["name"] = Helpers::DirToString(beforeS.dir);
        before["direction"] = bdir;

        Json::Value@ after = Json::Object();
        after["position"] = Vec3ToJson(afterS.pos);
        after["rotation"] = Vec3ToJson(afterS.rot);
        after["coord"]    = Nat3ToJson(afterS.coord);
        Json::Value@ adir = Json::Object();
        adir["enum"] = afterS.dir;
        adir["name"] = Helpers::DirToString(afterS.dir);
        after["direction"] = adir;

        ev["before"] = before;
        ev["after"]  = after;

        sink.AppendEvent(ev, flushEach);
        total++;
    }

    void RecordItemAdded(CGameCtnAnchoredObject@ it, uint index, bool flushEach) {
        auto when = Helpers::NowIso8601Utc();
        auto pos  = Helpers::GetItemLocation(it);
        auto rot  = Helpers::GetItemRotation(it);

        Json::Value@ ev = Json::Object();
        ev["type"]       = "item_added";
        ev["timestamp"]  = when;
        ev["seq"]        = int(seq++);
        ev["index"]      = int(index);

        Json::Value@ idv = Json::Object();
        idv["name"]   = Helpers::GetItemName(it);
        idv["itemId"] = it.ItemModel is null ? "" : Helpers::ToHex8(it.ItemModel.Id.Value);
        ev["id"] = idv;

        ev["position"] = Vec3ToJson(pos);
        ev["rotation"] = Vec3ToJson(rot);

        sink.AppendEvent(ev, flushEach);
        total++;
    }

    void RecordItemExisting(CGameCtnAnchoredObject@ it, uint index, bool flushEach) {
        auto pos  = Helpers::GetItemLocation(it);
        auto rot  = Helpers::GetItemRotation(it);

        Json::Value@ ev = Json::Object();
        ev["type"]              = "item_existing";
        ev["timestamp"]         = Helpers::NowIso8601Utc();
        ev["placementUnknown"]  = true;
        ev["seq"]               = int(seq++);
        ev["index"]             = int(index);

        Json::Value@ idv = Json::Object();
        idv["name"]   = Helpers::GetItemName(it);
        idv["itemId"] = it.ItemModel is null ? "" : Helpers::ToHex8(it.ItemModel.Id.Value);
        ev["id"] = idv;

        ev["position"] = Vec3ToJson(pos);
        ev["rotation"] = Vec3ToJson(rot);

        sink.AppendEvent(ev, false);
        total++;
    }

    void RecordItemRemoved(ItemSnap@ oldS, bool flushEach) {
        Json::Value@ ev = Json::Object();
        ev["type"]       = "item_removed";
        ev["timestamp"]  = Helpers::NowIso8601Utc();
        ev["seq"]        = int(seq++);

        Json::Value@ idv = Json::Object();
        idv["name"]   = oldS.name;
        idv["itemId"] = Helpers::ToHex8(oldS.modelId);
        ev["id"] = idv;

        Json::Value@ last = Json::Object();
        last["position"] = Vec3ToJson(oldS.pos);
        last["rotation"] = Vec3ToJson(oldS.rot);
        ev["last"] = last;

        sink.AppendEvent(ev, flushEach);
        total++;
    }

    void RecordItemUpdated(ItemSnap@ beforeS, ItemSnap@ afterS, bool flushEach) {
        Json::Value@ ev = Json::Object();
        ev["type"]       = "item_updated";
        ev["timestamp"]  = Helpers::NowIso8601Utc();
        ev["seq"]        = int(seq++);

        Json::Value@ idv = Json::Object();
        idv["name"]   = afterS.name;
        idv["itemId"] = Helpers::ToHex8(afterS.modelId);
        ev["id"] = idv;

        Json::Value@ before = Json::Object();
        before["position"] = Vec3ToJson(beforeS.pos);
        before["rotation"] = Vec3ToJson(beforeS.rot);

        Json::Value@ after = Json::Object();
        after["position"] = Vec3ToJson(afterS.pos);
        after["rotation"] = Vec3ToJson(afterS.rot);

        ev["before"] = before;
        ev["after"]  = after;

        sink.AppendEvent(ev, flushEach);
        total++;
    }

    void Flush(bool pretty = false) { sink.Flush(pretty); }
}

JsonSink@ gSink = null;
Recorder@ gRec  = null;

void InitOffsets(uint16 dirOffsetSetting) { Helpers::InitOffsets(dirOffsetSetting); }

void Recorder_Start(const string &in outFile) {
    if (gRec !is null) return;
    @gSink = JsonSink(outFile);
    @gRec  = Recorder(gSink);
}

void Recorder_StopAndFlush() {
    if (gRec is null) return;
    gRec.Flush(true);
    @gRec = null;
    @gSink = null;
}

bool Recorder_IsActive() { return gRec !is null; }
void Recorder_Update(bool flushEach, int fullScanSec) { if (gRec !is null) gRec.Update(flushEach, fullScanSec); }
uint Recorder_EventCount() { return gRec is null ? 0 : gRec.EventCount(); }
void Recorder_Flush(bool pretty = false) { if (gRec !is null) gRec.Flush(pretty); }
void Recorder_BackfillExisting(bool flushEach) { if (gRec !is null) gRec.BackfillExisting(flushEach); }

}
