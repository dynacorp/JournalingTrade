//+------------------------------------------------------------------+
//| PAM/ZoneEngine.mqh  —  Smart zones: OB, FVG, Breaker blocks    |
//|                                                                  |
//| Order Block (OB):                                                |
//|   Last candle in the OPPOSITE direction before a displacement   |
//|   that broke structure. The institution's "footprint."          |
//|                                                                  |
//| Fair Value Gap (FVG / Imbalance):                               |
//|   Three-candle pattern where candle[i+2] and candle[i] don't    |
//|   overlap — price moved so fast it left a gap in the market.   |
//|                                                                  |
//| Breaker Block:                                                   |
//|   An OB whose high/low has been broken — now flips role.        |
//+------------------------------------------------------------------+
#ifndef PAM_ZONE_MQH
#define PAM_ZONE_MQH
#include "Context.mqh"

//+------------------------------------------------------------------+
// Detect displacement candle — the "impulse" that creates OBs/FVGs
// Returns true if candle[i] is a displacement bar.
//+------------------------------------------------------------------+
bool IsDisplacement(int i,
                    const double &open[],
                    const double &high[],
                    const double &low[],
                    const double &close[],
                    const double &atr[],
                    double        thresh)
{
   if(i < 0 || atr[i] < 1e-10) return false;
   double body     = MathAbs(close[i] - open[i]);
   double bodyRatio = body / (high[i] - low[i] + 1e-10);
   double bodyVsAtr = body / atr[i];
   return (bodyVsAtr >= thresh && bodyRatio >= 0.55);
}

//+------------------------------------------------------------------+
// ZoneEngine_Compute
//   Scans for OBs, FVGs, and Breaker Blocks.
//   Marks ctx.hasBullOB, ctx.hasBearOB, ctx.hasBullFVG, etc.
//+------------------------------------------------------------------+
void ZoneEngine_Compute(SPAMContext    &ctx,
                         const double   &open[],
                         const double   &high[],
                         const double   &low[],
                         const double   &close[],
                         const datetime &time[],
                         const double   &atr[],
                         int             total)
{
   ctx.nZones         = 0;
   ctx.hasBullOB      = false;
   ctx.hasBearOB      = false;
   ctx.hasBullFVG     = false;
   ctx.hasBearFVG     = false;
   ctx.hasBullBreaker = false;
   ctx.hasBearBreaker = false;

   int limit = MathMin(ctx.lookback, total - 3);

   // =================================================================
   // PASS 1: Order Blocks
   // A bullish OB  = last bearish candle before a bullish displacement
   //                 that ultimately broke above a prior swing high.
   // A bearish OB  = last bullish candle before a bearish displacement.
   // We cap at the last 5 OBs per side to avoid overdrawing.
   // =================================================================
   int bullObCount = 0, bearObCount = 0;

   for(int i = 1; i <= limit && (bullObCount < 5 || bearObCount < 5); i++)
   {
      if(!IsDisplacement(i, open, high, low, close, atr, ctx.dispThresh)) continue;

      bool dispBull = (close[i] > open[i]);
      bool dispBear = (close[i] < open[i]);

      if(dispBull && bullObCount < 5 && ctx.nZones < PAM_MAX_ZONES - 1)
      {
         // Find the last bearish candle before this displacement (i+1, i+2, ...)
         for(int j = i + 1; j <= MathMin(i + 5, limit); j++)
         {
            if(close[j] < open[j])   // bearish candle found
            {
               // Ensure it wasn't mitigated: price hasn't returned to its range
               double obTop = high[j];
               double obBot = low[j];
               bool mitigated = false;
               for(int m = i - 1; m >= 0; m--)
               {
                  if(low[m] <= obBot + (obTop - obBot) * 0.5) { mitigated = true; break; }
               }

               SZone z;
               z.type      = ZONE_OB_BULL;
               z.top       = obTop;
               z.bot       = obBot;
               z.timeStart = time[j];
               z.mitigated = mitigated;
               z.strength  = mitigated ? 1 : 3;
               ctx.zones[ctx.nZones] = z;
               ctx.nZones++;
               ctx.hasBullOB = true;
               bullObCount++;
               break;
            }
         }
      }
      else if(dispBear && bearObCount < 5 && ctx.nZones < PAM_MAX_ZONES - 1)
      {
         // Find the last bullish candle before this displacement
         for(int j = i + 1; j <= MathMin(i + 5, limit); j++)
         {
            if(close[j] > open[j])   // bullish candle found
            {
               double obTop = high[j];
               double obBot = low[j];
               bool mitigated = false;
               for(int m = i - 1; m >= 0; m--)
               {
                  if(high[m] >= obTop - (obTop - obBot) * 0.5) { mitigated = true; break; }
               }

               SZone z;
               z.type      = ZONE_OB_BEAR;
               z.top       = obTop;
               z.bot       = obBot;
               z.timeStart = time[j];
               z.mitigated = mitigated;
               z.strength  = mitigated ? 1 : 3;
               ctx.zones[ctx.nZones] = z;
               ctx.nZones++;
               ctx.hasBearOB = true;
               bearObCount++;
               break;
            }
         }
      }
   }

   // =================================================================
   // PASS 2: Fair Value Gaps (FVGs)
   // Three bars: [i+2] old → [i+1] middle → [i] new (series order)
   // Bullish FVG: low[i]    > high[i+2]  (gap UP between outer bars)
   // Bearish FVG: high[i]   < low[i+2]   (gap DOWN between outer bars)
   // Minimum size: ctx.minFvgAtr * atr
   // =================================================================
   int bullFvgCount = 0, bearFvgCount = 0;

   for(int i = 1; i < limit - 1; i++)
   {
      if(ctx.nZones >= PAM_MAX_ZONES - 1) break;

      double minSz = ctx.minFvgAtr * atr[i];

      // Bullish FVG
      if(low[i] > high[i + 2] && (low[i] - high[i + 2]) >= minSz && bullFvgCount < 6)
      {
         double fTop = low[i];
         double fBot = high[i + 2];
         bool filled = false;
         for(int m = i - 1; m >= 0; m--)
            if(low[m] <= fBot + (fTop - fBot) * 0.5) { filled = true; break; }

         if(!filled || bullFvgCount < 3)   // show up to 3 unfilled + 3 filled
         {
            SZone z;
            z.type      = ZONE_FVG_BULL;
            z.top       = fTop;
            z.bot       = fBot;
            z.timeStart = time[i + 1];
            z.mitigated = filled;
            z.strength  = filled ? 1 : 4;
            ctx.zones[ctx.nZones] = z;
            ctx.nZones++;
            ctx.hasBullFVG = true;
            bullFvgCount++;
         }
      }
      // Bearish FVG
      else if(high[i] < low[i + 2] && (low[i + 2] - high[i]) >= minSz && bearFvgCount < 6)
      {
         double fTop = low[i + 2];
         double fBot = high[i];
         bool filled = false;
         for(int m = i - 1; m >= 0; m--)
            if(high[m] >= fBot + (fTop - fBot) * 0.5) { filled = true; break; }

         if(!filled || bearFvgCount < 3)
         {
            SZone z;
            z.type      = ZONE_FVG_BEAR;
            z.top       = fTop;
            z.bot       = fBot;
            z.timeStart = time[i + 1];
            z.mitigated = filled;
            z.strength  = filled ? 1 : 4;
            ctx.zones[ctx.nZones] = z;
            ctx.nZones++;
            ctx.hasBearFVG = true;
            bearFvgCount++;
         }
      }
   }

   // =================================================================
   // PASS 3: Breaker Blocks
   // A bullish OB whose low has been broken → bearish breaker
   // A bearish OB whose high has been broken → bullish breaker
   // Check current price vs. existing OBs
   // =================================================================
   double curPrice = (total > 0) ? close[0] : 0;
   for(int i = 0; i < ctx.nZones; i++)
   {
      if(ctx.zones[i].type == ZONE_OB_BULL && curPrice < ctx.zones[i].bot)
      {
         ctx.zones[i].type  = ZONE_BREAKER_BEAR;
         ctx.hasBearBreaker = true;
      }
      else if(ctx.zones[i].type == ZONE_OB_BEAR && curPrice > ctx.zones[i].top)
      {
         ctx.zones[i].type  = ZONE_BREAKER_BULL;
         ctx.hasBullBreaker = true;
      }
   }
}

//+------------------------------------------------------------------+
// ZoneEngine_Draw
//+------------------------------------------------------------------+
void ZoneEngine_Draw(const SPAMContext &ctx,
                      const datetime   &time[],
                      int               total,
                      const string     &pfx)
{
   datetime t0 = time[0];

   for(int i = 0; i < ctx.nZones; i++)
   {
      SZone z = ctx.zones[i];

      bool drawThis = false;
      color fillCol = C'10,10,10', borderCol = clrSilver;
      string typeStr = "";
      ENUM_LINE_STYLE bStyle = STYLE_SOLID;
      int  borderW  = 1;

      switch(z.type)
      {
         case ZONE_OB_BULL:
            drawThis  = ctx.showOB;
            fillCol   = z.mitigated ? C'0,25,50'  : C'0,40,100';
            borderCol = ctx.obBullCol;
            typeStr   = z.mitigated ? "OB↑ (mit)" : "OB↑";
            break;
         case ZONE_OB_BEAR:
            drawThis  = ctx.showOB;
            fillCol   = z.mitigated ? C'40,10,10' : C'80,20,20';
            borderCol = ctx.obBearCol;
            typeStr   = z.mitigated ? "OB↓ (mit)" : "OB↓";
            break;
         case ZONE_FVG_BULL:
            drawThis  = ctx.showFVG;
            fillCol   = z.mitigated ? C'0,15,15'  : C'0,30,30';
            borderCol = ctx.fvgBullCol;
            typeStr   = z.mitigated ? "FVG↑ (filled)" : "FVG↑";
            bStyle    = STYLE_DASH;
            break;
         case ZONE_FVG_BEAR:
            drawThis  = ctx.showFVG;
            fillCol   = z.mitigated ? C'20,5,5'   : C'35,10,10';
            borderCol = ctx.fvgBearCol;
            typeStr   = z.mitigated ? "FVG↓ (filled)" : "FVG↓";
            bStyle    = STYLE_DASH;
            break;
         case ZONE_BREAKER_BULL:
            drawThis  = ctx.showBreaker;
            fillCol   = C'0,15,40';
            borderCol = C'80,200,255';
            typeStr   = "Breaker↑";
            bStyle    = STYLE_DOT;
            borderW   = 2;
            break;
         case ZONE_BREAKER_BEAR:
            drawThis  = ctx.showBreaker;
            fillCol   = C'40,5,5';
            borderCol = C'255,100,100';
            typeStr   = "Breaker↓";
            bStyle    = STYLE_DOT;
            borderW   = 2;
            break;
         default: break;
      }

      if(!drawThis) continue;

      string nm = pfx + "ZN" + IntegerToString(i);
      ObjectCreate(0, nm, OBJ_RECTANGLE, 0, z.timeStart, z.top, t0, z.bot);
      ObjectSetInteger(0, nm, OBJPROP_COLOR,      borderCol);
      ObjectSetInteger(0, nm, OBJPROP_STYLE,      ctx.outlineMode ? STYLE_DOT : bStyle);
      ObjectSetInteger(0, nm, OBJPROP_WIDTH,      ctx.outlineMode ? 1 : borderW);
      ObjectSetInteger(0, nm, OBJPROP_FILL,       !ctx.outlineMode);
      ObjectSetInteger(0, nm, OBJPROP_BGCOLOR,    fillCol);
      ObjectSetInteger(0, nm, OBJPROP_BACK,       true);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);

      // Zone label
      string lnm = pfx + "ZNL" + IntegerToString(i);
      ObjectCreate(0, lnm, OBJ_TEXT, 0, z.timeStart, z.top);
      ObjectSetString(0,  lnm, OBJPROP_TEXT,       typeStr);
      ObjectSetInteger(0, lnm, OBJPROP_COLOR,      borderCol);
      ObjectSetInteger(0, lnm, OBJPROP_FONTSIZE,   7);
      ObjectSetString(0,  lnm, OBJPROP_FONT,       "Consolas");
      ObjectSetInteger(0, lnm, OBJPROP_ANCHOR,     ANCHOR_LOWER);
      ObjectSetInteger(0, lnm, OBJPROP_SELECTABLE, false);
   }
}

#endif // PAM_ZONE_MQH
