//+------------------------------------------------------------------+
//| PAM/LiquidityEngine.mqh  —  Liquidity detection & sweeps       |
//|                                                                  |
//| Detects:                                                         |
//|  - Equal highs (buy-side liquidity pools)                       |
//|  - Equal lows  (sell-side liquidity pools)                      |
//|  - Liquidity sweeps (wick pierces level, body closes back)      |
//|  - Stop hunts (aggressive wick + immediate reversal)            |
//|  - Prior swing highs/lows as liquidity magnets                  |
//+------------------------------------------------------------------+
#ifndef PAM_LIQUIDITY_MQH
#define PAM_LIQUIDITY_MQH
#include "Context.mqh"

//+------------------------------------------------------------------+
// LiquidityEngine_Compute
//   Builds ctx.liq[] from:
//   1. Equal-high clusters  → buy-side liquidity above
//   2. Equal-low clusters   → sell-side liquidity below
//   3. Prior swing highs/lows from ctx.swings[]
//+------------------------------------------------------------------+
void LiquidityEngine_Compute(SPAMContext    &ctx,
                              const double   &high[],
                              const double   &low[],
                              const double   &close[],
                              const datetime &time[],
                              const double   &atr[],
                              int             total)
{
   ctx.nLiq        = 0;
   ctx.liqSweptBull = false;
   ctx.liqSweptBear = false;

   double tol   = atr[0] * ctx.eqTol;
   int    limit = MathMin(ctx.lookback, total - ctx.pivStr - 1);

   // --- Step 1: Equal-high clusters (buy-side liquidity) ---
   // Collect all confirmed pivot highs
   double pivHighPx[PAM_MAX_LIQ];
   datetime pivHighTm[PAM_MAX_LIQ];
   int    nPivH = 0;

   for(int i = ctx.pivStr; i <= limit; i++)
   {
      bool is_ph = true;
      for(int k = 1; k <= ctx.pivStr && is_ph; k++)
         if(i - k < 0 || i + k >= total) { is_ph = false; break; }
         else if(high[i - k] >= high[i] || high[i + k] >= high[i]) is_ph = false;
      if(!is_ph) continue;
      if(nPivH >= PAM_MAX_LIQ - 1) break;
      pivHighPx[nPivH] = high[i];
      pivHighTm[nPivH] = time[i];
      nPivH++;
   }

   // Cluster equal highs
   bool usedH[PAM_MAX_LIQ];
   ArrayInitialize(usedH, false);
   for(int a = 0; a < nPivH && ctx.nLiq < PAM_MAX_LIQ - 1; a++)
   {
      if(usedH[a]) continue;
      double clusterPrice = pivHighPx[a];
      datetime clusterTime = pivHighTm[a];
      int    clusterCount  = 1;
      for(int b = a + 1; b < nPivH; b++)
      {
         if(usedH[b]) continue;
         if(MathAbs(pivHighPx[b] - clusterPrice) <= tol)
         {
            clusterPrice = (clusterPrice * clusterCount + pivHighPx[b]) / (clusterCount + 1);
            if(pivHighTm[b] < clusterTime) clusterTime = pivHighTm[b];
            clusterCount++;
            usedH[b] = true;
         }
      }
      usedH[a] = true;

      // Only mark as significant liquidity if 2+ equal highs
      if(clusterCount < 2) continue;
      if(ctx.nLiq >= PAM_MAX_LIQ) break;

      SLiqLevel lv;
      lv.price    = clusterPrice;
      lv.timeLeft = clusterTime;
      lv.type     = LIQ_BUY_SIDE;
      lv.strength = MathMin(clusterCount, 5);
      lv.swept    = false;
      lv.sweepTime = 0;

      // Check if already swept: price wicked above but closed below
      for(int i = ctx.pivStr; i <= limit; i++)
      {
         if(time[i] <= clusterTime) continue;   // only look after the level formed
         if(high[i] > clusterPrice + tol * 0.3 && close[i] < clusterPrice)
         {
            lv.swept    = true;
            lv.sweepTime = time[i];
            ctx.liqSweptBear = true;   // buy-side swept = bearish event
            break;
         }
      }

      ctx.liq[ctx.nLiq] = lv;
      ctx.nLiq++;
   }

   // --- Step 2: Equal-low clusters (sell-side liquidity) ---
   double pivLowPx[PAM_MAX_LIQ];
   datetime pivLowTm[PAM_MAX_LIQ];
   int    nPivL = 0;

   for(int i = ctx.pivStr; i <= limit; i++)
   {
      bool is_pl = true;
      for(int k = 1; k <= ctx.pivStr && is_pl; k++)
         if(i - k < 0 || i + k >= total) { is_pl = false; break; }
         else if(low[i - k] <= low[i] || low[i + k] <= low[i]) is_pl = false;
      if(!is_pl) continue;
      if(nPivL >= PAM_MAX_LIQ - 1) break;
      pivLowPx[nPivL] = low[i];
      pivLowTm[nPivL] = time[i];
      nPivL++;
   }

   bool usedL[PAM_MAX_LIQ];
   ArrayInitialize(usedL, false);
   for(int a = 0; a < nPivL && ctx.nLiq < PAM_MAX_LIQ - 1; a++)
   {
      if(usedL[a]) continue;
      double clusterPrice = pivLowPx[a];
      datetime clusterTime = pivLowTm[a];
      int    clusterCount  = 1;
      for(int b = a + 1; b < nPivL; b++)
      {
         if(usedL[b]) continue;
         if(MathAbs(pivLowPx[b] - clusterPrice) <= tol)
         {
            clusterPrice = (clusterPrice * clusterCount + pivLowPx[b]) / (clusterCount + 1);
            if(pivLowTm[b] < clusterTime) clusterTime = pivLowTm[b];
            clusterCount++;
            usedL[b] = true;
         }
      }
      usedL[a] = true;
      if(clusterCount < 2) continue;
      if(ctx.nLiq >= PAM_MAX_LIQ) break;

      SLiqLevel lv;
      lv.price    = clusterPrice;
      lv.timeLeft = clusterTime;
      lv.type     = LIQ_SELL_SIDE;
      lv.strength = MathMin(clusterCount, 5);
      lv.swept    = false;
      lv.sweepTime = 0;

      // Check if already swept: price wicked below but closed above
      for(int i = ctx.pivStr; i <= limit; i++)
      {
         if(time[i] <= clusterTime) continue;
         if(low[i] < clusterPrice - tol * 0.3 && close[i] > clusterPrice)
         {
            lv.swept     = true;
            lv.sweepTime = time[i];
            ctx.liqSweptBull = true;   // sell-side swept = bullish event
            break;
         }
      }

      ctx.liq[ctx.nLiq] = lv;
      ctx.nLiq++;
   }
}

//+------------------------------------------------------------------+
// LiquidityEngine_Draw
//   Draws liquidity levels as dashed horizontal lines.
//   Swept levels shown as faded / struck-through.
//   Unswept shown prominently with strength-scaled width.
//+------------------------------------------------------------------+
void LiquidityEngine_Draw(const SPAMContext &ctx,
                           const datetime   &time[],
                           int               total,
                           const string     &pfx)
{
   if(!ctx.showLiq) return;

   datetime t0 = time[0];
   int leftBars = MathMin(ctx.lookback, total - 1);

   for(int i = 0; i < ctx.nLiq; i++)
   {
      SLiqLevel lv = ctx.liq[i];

      // Skip swept levels if toggle off
      if(lv.swept && !ctx.showSweeps) continue;

      // Skip levels that are too far away price-wise
      double dist = MathAbs(lv.price - ctx.lastSwH);
      // (draw all for now)

      bool isBuySide = (lv.type == LIQ_BUY_SIDE);
      color lc = lv.swept ? C'80,80,80' : ctx.liqCol;
      ENUM_LINE_STYLE ls = lv.swept ? STYLE_DOT : STYLE_DASH;
      int  lw = lv.swept ? 1 : MathMin(lv.strength, 3);

      string nm = pfx + "LIQ" + IntegerToString(i);
      datetime extRight = lv.swept ? lv.sweepTime : t0;
      ObjectCreate(0, nm, OBJ_TREND, 0, lv.timeLeft, lv.price, extRight, lv.price);
      ObjectSetInteger(0, nm, OBJPROP_COLOR,      lc);
      ObjectSetInteger(0, nm, OBJPROP_STYLE,      ls);
      ObjectSetInteger(0, nm, OBJPROP_WIDTH,      lw);
      ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT,  !lv.swept);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_BACK,       true);

      // Label
      string lbl = isBuySide ? "BSL" : "SSL";
      if(lv.swept) lbl += " ✓swept";
      lbl += " [" + IntegerToString(lv.strength) + "]";

      string lnm = pfx + "LIQL" + IntegerToString(i);
      double labelY = lv.price + (isBuySide ? ctx.atr * 0.15 : -ctx.atr * 0.15);
      ObjectCreate(0, lnm, OBJ_TEXT, 0, lv.timeLeft, labelY);
      ObjectSetString(0,  lnm, OBJPROP_TEXT,       lbl);
      ObjectSetInteger(0, lnm, OBJPROP_COLOR,      lc);
      ObjectSetInteger(0, lnm, OBJPROP_FONTSIZE,   7);
      ObjectSetString(0,  lnm, OBJPROP_FONT,       "Consolas");
      ObjectSetInteger(0, lnm, OBJPROP_ANCHOR,     isBuySide ? ANCHOR_LOWER : ANCHOR_UPPER);
      ObjectSetInteger(0, lnm, OBJPROP_SELECTABLE, false);

      // If swept — draw a sweep arrow
      if(lv.swept && ctx.showSweeps)
      {
         string snm = pfx + "LIQS" + IntegerToString(i);
         double arrowY = isBuySide ? lv.price + ctx.atr * 0.5 : lv.price - ctx.atr * 0.5;
         ObjectCreate(0, snm, OBJ_TEXT, 0, lv.sweepTime, arrowY);
         ObjectSetString(0,  snm, OBJPROP_TEXT,      isBuySide ? "⚡" : "⚡");
         ObjectSetInteger(0, snm, OBJPROP_COLOR,     C'255,200,0');
         ObjectSetInteger(0, snm, OBJPROP_FONTSIZE,  10);
         ObjectSetInteger(0, snm, OBJPROP_SELECTABLE,false);
      }
   }
}

//+------------------------------------------------------------------+
// Utility: count active (unswept) liquidity levels on each side
//+------------------------------------------------------------------+
int LiquidityEngine_CountBuySide(const SPAMContext &ctx)
{
   int n = 0;
   for(int i = 0; i < ctx.nLiq; i++)
      if(ctx.liq[i].type == LIQ_BUY_SIDE && !ctx.liq[i].swept) n++;
   return n;
}

int LiquidityEngine_CountSellSide(const SPAMContext &ctx)
{
   int n = 0;
   for(int i = 0; i < ctx.nLiq; i++)
      if(ctx.liq[i].type == LIQ_SELL_SIDE && !ctx.liq[i].swept) n++;
   return n;
}

// Nearest unswept level above current price
double LiquidityEngine_NearestAbove(const SPAMContext &ctx, double price)
{
   double best = DBL_MAX;
   for(int i = 0; i < ctx.nLiq; i++)
   {
      if(ctx.liq[i].swept) continue;
      if(ctx.liq[i].type != LIQ_BUY_SIDE) continue;
      if(ctx.liq[i].price > price && ctx.liq[i].price < best)
         best = ctx.liq[i].price;
   }
   return (best == DBL_MAX) ? 0 : best;
}

// Nearest unswept level below current price
double LiquidityEngine_NearestBelow(const SPAMContext &ctx, double price)
{
   double best = 0;
   for(int i = 0; i < ctx.nLiq; i++)
   {
      if(ctx.liq[i].swept) continue;
      if(ctx.liq[i].type != LIQ_SELL_SIDE) continue;
      if(ctx.liq[i].price < price && ctx.liq[i].price > best)
         best = ctx.liq[i].price;
   }
   return best;
}

#endif // PAM_LIQUIDITY_MQH
