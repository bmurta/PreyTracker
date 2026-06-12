# PreyTracker media/ — texture pack for the Hunt Board UI

All files: 32-bit uncompressed TGA with alpha, power-of-two dimensions, WoW-ready.
Reference in Lua as `"Interface\\AddOns\\PreyTracker\\media\\<name>"` (extension optional).

White textures are **tintable** — set the actual color with `tex:SetVertexColor(r, g, b, a)`.
Colored textures (trophy, gem) are used as-is.

## Chrome (white, tintable)

| File | Size | Use |
|---|---|---|
| `panel_bg.tga` | 64×64 | Rounded card/panel background. Nine-slice: `tex:SetTextureSliceMargins(16,16,16,16)` + `tex:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)`. Tint to surface color (e.g. 0.10, 0.11, 0.15). |
| `panel_border.tga` | 64×64 | Matching rounded 3px border. Same slice margins. Tint per state (difficulty, selection violet, in-progress gold). |
| `pill_bg.tga` | 64×32 | Status badges, filter pills, difficulty tags. Slice margins (16,8,16,8). |
| `pill_border.tga` | 64×32 | Pill outline, same margins. |
| `glow_radial.tga` | 128×128 | Soft round glow: status-dot halos, hover. Use `tex:SetBlendMode("ADD")`. Also the void creature's eyes (tint violet, ~6px). |
| `card_glow.tga` | 128×128 | Outer glow ring behind the selected card. Slice margins 32. ADD blend, tint violet. |

## Model stage

| File | Size | Use |
|---|---|---|
| `zone_glow.tga` | 256×128 | Elliptical backdrop in the model viewport. Tint with the zone color (Config `ZONE_COLOR`), alpha ~0.4. |
| `platform.tga` | 256×64 | Pedestal ellipse under the model. Tint zone color. |

## Creature silhouettes (white, tintable) — 256×128

`sil_stag.tga` (Eversong), `sil_cat.tga` (Zul'Aman), `sil_bat.tga` (Harandar), `sil_void.tga` (Voidstorm).
Placeholders until real 3D portraits: tint near-black (0.02, 0.03, 0.04) over the zone glow.
Swap for a `ModelScene`/`PlayerModel` frame + `SetDisplayInfo(displayID)` once a questID → creature displayID table exists.

## Icons

| File | Size | Tint | Use |
|---|---|---|---|
| `icon_paw.tga` | 64×64 | white → any | Logo, minimap button. |
| `icon_trophy.tga` | 64×64 | pre-colored | Achievement chip: hunt still needed for Prey: Nightmare Mode III. |
| `icon_check.tga` | 64×64 | white → green | Achievement criteria complete. |
| `icon_gem.tga` | 64×64 | pre-colored | Anguish currency chip. |
| `icon_reload.tga` | 64×64 | white → blue | Rescan button. |
| `icon_close.tga` | 32×32 | white → grey | Close button. |
| `icon_dot.tga` | 32×32 | white → any | Status dots, zone dots (crisper than glow_radial at small sizes). |
| `icon_skull.tga` | 64×64 | white → red | Nightmare map-pin glyph (eyes are transparent cutouts). |
| `icon_target.tga` | 64×64 | white → any | Normal/Hard map-pin glyph. |
| `pin.tga` | 64×64 | white → difficulty | Map pin teardrop body. |

## Lua snippets

```lua
-- rounded card
local bg = card:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetTexture("Interface\\AddOns\\PreyTracker\\media\\panel_bg")
bg:SetTextureSliceMargins(16, 16, 16, 16)
bg:SetTextureSliceMode(Enum.UITextureSliceMode.Stretched)
bg:SetVertexColor(0.10, 0.11, 0.15, 1)

-- selected-card glow
local glow = card:CreateTexture(nil, "BACKGROUND", nil, -1)
glow:SetPoint("TOPLEFT", -10, 10); glow:SetPoint("BOTTOMRIGHT", 10, -10)
glow:SetTexture("Interface\\AddOns\\PreyTracker\\media\\card_glow")
glow:SetTextureSliceMargins(32, 32, 32, 32)
glow:SetBlendMode("ADD")
glow:SetVertexColor(0.77, 0.30, 0.85)
```

Note: `SetTextureSliceMargins` exists on retail 10.0+; the Midnight client has it.
Regenerate any of these with `tga_pack.py` (SVG sources inside).
