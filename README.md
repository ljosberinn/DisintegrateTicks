Adds ticks of Disintegrate to the default UI cast bar, indicating when it's safe to chain or clip the current channel.

- https://addons.wago.io/addons/disintegrateticks
- https://curseforge.com/wow/addons/disintegrateticks

## Features

Apologies for the unwieldy API but I haven't had the time yet to create a proper UI for this.

## Change Color

Find a color you like, you can just google `color picker`. Copy the RGB value and then use:

```
/run DisintegrateTicksFrame:SetTickColor(r, g, b, a)
```

Alpha is optional and will default to 1.

For example:

```
/run DisintegrateTicksFrame:SetTickColor(161, 66, 71)
```

You'll see a brief confirmation in chat. The default color is white, to restore it use:

```
/run DisintegrateTicksFrame:SetTickColor(1, 1, 1, 1)
```

## Toggle Mass Disintegrate Clip Warning

Default off, this will show `DON'T CLIP` close to the cast bar when you're channeling a `Mass Disintegrate` as the default UI doesn't provide this information.

Available commands:

### Available Commands

#### Enable/Disable

```
/run DisintegrateTicksFrame:ToggleMassDisintegrateClipWarning()
```

Brief confirmation in chat.

#### Change Font Size

```
/run DisintegrateTicksFrame:SetClipWarningFontSize(size)
```

Brief confirmation in chat. Omission of size resets it to 18.

#### Change Text

```
/run DisintegrateTicksFrame:SetClipWarningText(text)
```

Brief confirmation in chat. Omission of text resets it to `DON'T CLIP`.

### Change Position

By default, the warning will be 100px above the cast bar. This may not be suited for your layout, so you can change it with:

```
/run DisintegrateTicksFrame:SetClipWarningPosition(point, x, y)
```

Available points are `"TOP"` and `"BOTTOM"`. The quotes matter.

### Change Color

Default white, you can change it with:

```
/run DisintegrateTicksFrame:SetClipWarningColor(r, g, b, a)
```

Alpha is optional and will default to 1.

### Supported Cast Bars

- NephUI
- UnhaltedUnitFrames
- BetterCooldownManager
- MidnightSimpleUnitFrames
- ActionBarsEnhanced

If you have multiple cast bars shown, e.g. from both unit frames and BetterCooldownManager, disable all but one, otherwise they'll compete.
