//+------------------------------------------------------------------+
//| PAM/DailyBiasEngine.mqh  —  Daily & Weekly Bias Reference       |
//|                                                                  |
//| SMC / ICT Core Concept:                                         |
//|   Every day trades relative to the PREVIOUS day's range. The    |
//|   location of current price versus PDH/PDL/PDC immediately      |
//|   tells you the institutional intention for the session:         |
//|                                                                  |
//|   Above PDH  → Expansion / breakout day. Trend continuation     |
//|                is the highest-probability scenario.              |
//|   Inside day → Range contraction. Price is balanced; expect     |
//|                accumulation or manipulation before a breakout.   |
//|   Below PDL  → Bearish breakdown. Distribution from yesterday's  |
//|                highs is the likely narrative.                    |
//|                                                                  |
//|   PDM (midpoint) = 50% of previous day's range. Price above    |
//|   PDM = intraday bullish delivery. Below = bearish delivery.    |
//|                                                                  |
//|   WEEKLY OPEN — price above the weekly open all week signals    |
//|   institutional buy-side accumulation at the weekly level.      |
//|   Below weekly open = sell-side institutional distribution.     |
//|   The weekly open is the most important reference level on the  |
//|   higher timeframe chart for SMC practitioners.                 |
//+------------------------------------------------------------------+
#ifndef PAM_DAILYBIAS_MQH
#define PAM_DAILYBIAS_MQH
#include "Context.mqh"

//+------------------------------------------------------------------+
// DailyBiasEngine_Compute
//   Uses CopyRates on D1 and W1 to populate PDH/PDL/PDC/PDM and
//   weekly open. Sets ctx.dailyBias and ctx.weeklyBias.
//+------------------------------------------------------------------+
void DailyBiasEngine_Compute(SPAMContext &ctx, double curPrice)
{
   ctx.pdHigh     = 0;
   ctx.pdLow      = 0;
   ctx.pdClose    = 0;
   ctx.pdMid      = 0;
   ctx.weeklyOpen = 0;
   ctx.dailyBias  = TREND_UNDEFINED;
   ctx.weeklyBias = TREND_UNDEFINED;

   if(!ctx.showDailyBias) return;

   // ─── Previous day levels ─────────────────────────────────────
   // [0]=today forming, [1]=yesterday complete
   MqlRates dr[];
   ArraySetAsSeries(dr, true);
   if(CopyRates(_Symbol, PERIOD_D1, 0, 3, dr) < 2) return;

   ctx.pdHigh  = dr[1].high;
   ctx.pdLow   = dr[1].low;
   ctx.pdClose = dr[1].close;
   ctx.pdMid   = (dr[1].high + dr[1].low) * 0.5;

   // ─── Weekly open ─────────────────────────────────────────────
   MqlRates wr[];
   ArraySetAsSeries(wr, true);
   if(CopyRates(_Symbol, PERIOD_W1, 0, 2, wr) >= 1)
      ctx.weeklyOpen = wr[0].open;

   // ─── Daily bias ──────────────────────────────────────────────
   if(curPrice > ctx.pdHigh)     ctx.dailyBias = TREND_BULLISH;
   else if(curPrice < ctx.pdLow) ctx.dailyBias = TREND_BEARISH;
   else                          ctx.dailyBias = TREND_RANGING;

   // ─── Weekly bias ─────────────────────────────────────────────
   if(ctx.weeklyOpen > 0)
   {
      if(curPrice > ctx.weeklyOpen)      ctx.weeklyBias = TREND_BULLISH;
      else if(curPrice < ctx.weeklyOpen) ctx.weeklyBias = TREND_BEARISH;
      else                               ctx.weeklyBias = TREND_RANGING;
   }
}

//+------------------------------------------------------------------+
// DailyBiasEngine_Draw
//   Draws horizontal reference lines for PDH, PDL, PDC, PDM and
//   weekly open. Lines extend from yesterday's open rightward.
//+------------------------------------------------------------------+
void DailyBiasEngine_Draw(const SPAMContext &ctx,
                           const datetime   &time[],
                           int               total,
                           const string     &pfx)
{
   if(!ctx.showDailyBias) return;
   if(ctx.pdHigh <= 0)    return;

   // Anchor left edge at start of lookback (not too far left for readability)
   int      leftBar  = MathMin(ctx.lookback, total - 1);
   datetime leftTime = time[leftBar];
   datetime nowTime  = time[0];

   // Helper lambda pattern: build name, delete old, create new line + label
   struct SLvl { double price; string tag; string lbl; color lineCol; color lblCol; int sty; int wid; int anc; };

   // Build the set of levels to draw
   int nLvls = 0;
   SLvl lvls[5];

   if(ctx.showPDLevels)
   {
      // PDH
      lvls[nLvls].price   = ctx.pdHigh;
      lvls[nLvls].tag     = "PDH";
      lvls[nLvls].lbl     = "PDH";
      lvls[nLvls].lineCol = C'180,55,55';
      lvls[nLvls].lblCol  = C'200,80,80';
      lvls[nLvls].sty     = STYLE_DASH;
      lvls[nLvls].wid     = 1;
      lvls[nLvls].anc     = ANCHOR_LOWER;
      nLvls++;

      // PDL
      lvls[nLvls].price   = ctx.pdLow;
      lvls[nLvls].tag     = "PDL";
      lvls[nLvls].lbl     = "PDL";
      lvls[nLvls].lineCol = C'55,180,55';
      lvls[nLvls].lblCol  = C'80,200,80';
      lvls[nLvls].sty     = STYLE_DASH;
      lvls[nLvls].wid     = 1;
      lvls[nLvls].anc     = ANCHOR_UPPER;
      nLvls++;

      // PDC
      lvls[nLvls].price   = ctx.pdClose;
      lvls[nLvls].tag     = "PDC";
      lvls[nLvls].lbl     = "PDC";
      lvls[nLvls].lineCol = C'130,130,160';
      lvls[nLvls].lblCol  = C'160,160,190';
      lvls[nLvls].sty     = STYLE_DOT;
      lvls[nLvls].wid     = 1;
      lvls[nLvls].anc     = ANCHOR_LOWER;
      nLvls++;

      // PDM (midpoint)
      lvls[nLvls].price   = ctx.pdMid;
      lvls[nLvls].tag     = "PDM";
      lvls[nLvls].lbl     = "PDM";
      lvls[nLvls].lineCol = C'80,80,120';
      lvls[nLvls].lblCol  = C'100,100,150';
      lvls[nLvls].sty     = STYLE_DOT;
      lvls[nLvls].wid     = 1;
      lvls[nLvls].anc     = ANCHOR_UPPER;
      nLvls++;
   }

   if(ctx.showWeeklyOpen && ctx.weeklyOpen > 0)
   {
      lvls[nLvls].price   = ctx.weeklyOpen;
      lvls[nLvls].tag     = "WO";
      lvls[nLvls].lbl     = "W.Open";
      lvls[nLvls].lineCol = C'200,170,0';
      lvls[nLvls].lblCol  = C'230,200,0';
      lvls[nLvls].sty     = STYLE_DASH;
      lvls[nLvls].wid     = 1;
      lvls[nLvls].anc     = ANCHOR_LOWER;
      nLvls++;
   }

   for(int k = 0; k < nLvls; k++)
   {
      string nm  = pfx + "DB" + lvls[k].tag;
      string lnm = pfx + "DB" + lvls[k].tag + "L";

      ObjectCreate(0, nm, OBJ_TREND, 0, leftTime, lvls[k].price, nowTime, lvls[k].price);
      ObjectSetInteger(0, nm, OBJPROP_COLOR,      lvls[k].lineCol);
      ObjectSetInteger(0, nm, OBJPROP_STYLE,      lvls[k].sty);
      ObjectSetInteger(0, nm, OBJPROP_WIDTH,      lvls[k].wid);
      ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT,  true);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_BACK,       true);

      ObjectCreate(0, lnm, OBJ_TEXT, 0, leftTime, lvls[k].price);
      ObjectSetString(0,  lnm, OBJPROP_TEXT,      lvls[k].lbl);
      ObjectSetInteger(0, lnm, OBJPROP_COLOR,     lvls[k].lblCol);
      ObjectSetInteger(0, lnm, OBJPROP_FONTSIZE,  7);
      ObjectSetString(0,  lnm, OBJPROP_FONT,      "Consolas");
      ObjectSetInteger(0, lnm, OBJPROP_ANCHOR,    lvls[k].anc);
      ObjectSetInteger(0, lnm, OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0, lnm, OBJPROP_BACK,      true);
   }
}

//+------------------------------------------------------------------+
// DailyBiasEngine_DashString
//   Dashboard row: daily position + weekly alignment. Mode-aware.
//+------------------------------------------------------------------+
string DailyBiasEngine_DashString(const SPAMContext &ctx, double curPrice, EMode mode)
{
   if(!ctx.showDailyBias || ctx.pdHigh <= 0)
      return "  Daily Bias  no D1 data";

   // Daily position string
   string dayPos;
   if(ctx.dailyBias == TREND_BULLISH)       dayPos = "ABOVE PDH";
   else if(ctx.dailyBias == TREND_BEARISH)  dayPos = "BELOW PDL";
   else
   {
      // Inside day — show which half
      if(curPrice >= ctx.pdMid)  dayPos = "inside — upper half";
      else                        dayPos = "inside — lower half";
   }

   // Weekly alignment note
   string wkNote = "";
   if(ctx.weeklyBias == TREND_BULLISH)     wkNote = " | WO ↑";
   else if(ctx.weeklyBias == TREND_BEARISH) wkNote = " | WO ↓";

   // Mode-specific detail
   string detail = "";
   switch(mode)
   {
      case MODE_BEGINNER:
         if(ctx.dailyBias == TREND_BULLISH)      detail = " — expansion day";
         else if(ctx.dailyBias == TREND_BEARISH) detail = " — breakdown day";
         else                                    detail = " — inside range";
         break;
      case MODE_ADVANCED:
         if(ctx.dailyBias == TREND_BULLISH)      detail = " (BRK)";
         else if(ctx.dailyBias == TREND_BEARISH) detail = " (BDN)";
         break;
      case MODE_INSTITUTIONAL:
         if(ctx.dailyBias == TREND_BULLISH && ctx.weeklyBias == TREND_BULLISH)
            detail = " ✓ expansion confluence";
         else if(ctx.dailyBias == TREND_BEARISH && ctx.weeklyBias == TREND_BEARISH)
            detail = " ✓ breakdown confluence";
         else if(ctx.dailyBias != ctx.weeklyBias && ctx.dailyBias != TREND_RANGING)
            detail = " ✗ weekly divergence";
         break;
   }

   return StringFormat("  Daily Bias  %s%s%s", dayPos, detail, wkNote);
}

#endif // PAM_DAILYBIAS_MQH
