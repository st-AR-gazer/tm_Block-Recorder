// ty to XertroV and e++ for the offsests and some of the funcs

namespace TMBR_Core {
namespace Helpers {

    uint16 O_CGameCtnBlock_DirOffset = 0;
    uint16 FreeBlockPosOffset = 0;
    uint16 FreeBlockRotOffset = 0;
    uint16 O_CGameCtnBlock_BlockUniqueID = 0;

    void InitOffsets(uint16 dirOffsetSetting) {
        O_CGameCtnBlock_DirOffset = dirOffsetSetting;
        FreeBlockPosOffset = O_CGameCtnBlock_DirOffset + 0x8;
        FreeBlockRotOffset = FreeBlockPosOffset + 0xC;
        O_CGameCtnBlock_BlockUniqueID = O_CGameCtnBlock_DirOffset + 0x34;
        log("[TMBR] Offsets: Dir=0x" + ToHex8(O_CGameCtnBlock_DirOffset) + " FreePos=0x" + ToHex8(FreeBlockPosOffset) + " FreeRot=0x" + ToHex8(FreeBlockRotOffset) + " UniqueID=0x" + ToHex8(O_CGameCtnBlock_BlockUniqueID), LogLevel::Info, 16, "InitOffsets");
    }

    string ToHex8(uint v) {
        const string d = "0123456789ABCDEF";
        string s = "";
        for (int i = 7; i >= 0; --i) {
            uint nib = (v >> (i * 4)) & 0xF;
            s += d.SubStr(int(nib), 1);
        }
        return s;
    }

    const vec3 HALF_COORD = vec3(16, 4, 16);

    vec3 CoordToPos(const nat3 &in c) {
        return vec3(float(c.x) * 32.0f, float(c.y) * 8.0f, float(c.z) * 32.0f);
    }

    nat3 PosToCoord(const vec3 &in p) {
        return nat3(uint(Math::Floor(p.x / 32.0f)), uint(Math::Floor(p.y / 8.0f)), uint(Math::Floor(p.z / 32.0f)));
    }

    vec3 HalfPivotCorrectionForDir(int dir) {
        if (dir == 0) return vec3(0, 0, 0);
        if (dir == 1) return vec3(0, 0, 32);
        if (dir == 2) return vec3(32, 0, 32);
        if (dir == 3) return vec3(32, 0, 0);
        return vec3(0, 0, 0);
    }

    float DirToYawDeg(int dir) {
        if (dir == 0) return 0.0f;
        if (dir == 1) return 90.0f;
        if (dir == 2) return 180.0f;
        if (dir == 3) return 270.0f;
        return 0.0f;
    }

    string DirToString(int dir) {
        if (dir == 0) return "North";
        if (dir == 1) return "East";
        if (dir == 2) return "South";
        if (dir == 3) return "West";
        return "Unknown";
    }

    vec3 Nat3ToVec3(nat3 n) { return vec3(float(n.x), float(n.y), float(n.z)); }

    CGameCtnBlockInfoVariant@ GetActiveVariant(CGameCtnBlock@ b) {
        if (b is null || b.BlockInfo is null) return null;
        auto bi = b.BlockInfo;
        uint bix = b.BlockInfoVariantIndex;
        bool ground = b.IsGround;
        if (bix == 0) {
            auto @biv = ground ? cast<CGameCtnBlockInfoVariant>(bi.VariantBaseGround)
                               : cast<CGameCtnBlockInfoVariant>(bi.VariantBaseAir);
            if (biv is null) {
                @biv = ground ? cast<CGameCtnBlockInfoVariant>(bi.VariantGround)
                              : cast<CGameCtnBlockInfoVariant>(bi.VariantAir);
            }
            return biv;
        } else {
            if (ground) {
                if (bix - 1 < bi.AdditionalVariantsGround.Length)
                    return cast<CGameCtnBlockInfoVariant>(bi.AdditionalVariantsGround[bix - 1]);
            } else {
                if (bix - 1 < bi.AdditionalVariantsAir.Length)
                    return cast<CGameCtnBlockInfoVariant>(bi.AdditionalVariantsAir[bix - 1]);
            }
        }
        return null;
    }

    vec3 GetBlockCoordSize(CGameCtnBlock@ b) {
        auto @biv = GetActiveVariant(b);
        if (biv is null) return vec3(1, 1, 1);
        auto s = biv.Size;
        return vec3(float(s.x), float(s.y), float(s.z));
    }

    bool IsBlockFree(CGameCtnBlock@ b) { return int(b.CoordX) < 0; }

    vec3 BlockCoordAndSizeToPos(nat3 bCoord, const vec3 &in coordSize, int dir) {
        vec3 c = Nat3ToVec3(bCoord);
        if (dir == 1)      c.x += coordSize.z - 1.0f;
        else if (dir == 2) { c.x += coordSize.x - 1.0f; c.z += coordSize.z - 1.0f; }
        else if (dir == 3) c.z += coordSize.x - 1.0f;
        auto pos = CoordToPos(nat3(uint(c.x), uint(c.y), uint(c.z)));
        pos += HalfPivotCorrectionForDir(dir);
        return pos;
    }

    vec3 GetBlockLocation(CGameCtnBlock@ b) {
        if (b is null) return vec3();
        if (IsBlockFree(b)) {
            return Dev::GetOffsetVec3(b, FreeBlockPosOffset);
        }
        return BlockCoordAndSizeToPos(b.Coord, GetBlockCoordSize(b), int(b.Dir));
    }

    vec3 GetBlockRotation(CGameCtnBlock@ b) {
        if (b is null) return vec3();
        if (IsBlockFree(b)) {
            auto ypr = Dev::GetOffsetVec3(b, FreeBlockRotOffset);
            return vec3(ypr.y, ypr.x, ypr.z);
        }
        return vec3(0.0f, DirToYawDeg(int(b.Dir)), 0.0f);
    }

    nat3 GetBlockCoord(CGameCtnBlock@ b) {
        if (b is null) return nat3(0, 0, 0);
        if (IsBlockFree(b)) return PosToCoord(GetBlockLocation(b));
        return b.Coord;
    }

    uint GetBlockUniqueID(CGameCtnBlock@ b) {
        if (b is null) return 0;
        return Dev::GetOffsetUint32(b, O_CGameCtnBlock_BlockUniqueID);
    }

    vec3 GetItemLocation(CGameCtnAnchoredObject@ item) {
        return item is null ? vec3() : item.AbsolutePositionInMap;
    }

    vec3 GetItemRotation(CGameCtnAnchoredObject@ item) {
        if (item is null) return vec3();
        return vec3(item.Pitch, item.Yaw, item.Roll);
    }

    string GetBlockName(CGameCtnBlock@ b) {
        if (b is null) return "";
        if (b.BlockInfo !is null && b.BlockInfo.Name.Length > 0) return string(b.BlockInfo.Name);
        return "DescId:0x" + ToHex8(b.DescId.Value);
    }

    string GetItemName(CGameCtnAnchoredObject@ item) {
        if (item is null) return "";
        if (item.ItemModel !is null) {
            if (item.ItemModel.Name.Length > 0) return string(item.ItemModel.Name);
            return "ItemId:0x" + ToHex8(item.ItemModel.Id.Value);
        }
        return "UnknownItem";
    }

    string NowIso8601Utc() {
        return Time::FormatStringUTC("%Y-%m-%dT%H:%M:%SZ");
    }

}} 
