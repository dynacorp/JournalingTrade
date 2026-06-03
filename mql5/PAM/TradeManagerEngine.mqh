//+------------------------------------------------------------------+
//| PAM/TradeManagerEngine.mqh  —  SL / TP / R:R Trade Management  |
//|                                                                  |
//| SMC / ICT Core Concept:                                         |
//|   Institutional traders define risk BEFORE entry. Structure     |
//|   tells you WHERE you are wrong — the last confirmed HL (bull)  |
//|   or LH (bear) is the invalidation level. Liquidity is the      |
//|   draw — the nearest unswept pool is the natural TP target.     |
//|                                                                  |
//|   Stop Loss  — beyond the last confirmed structural swing point  |
//|                (HL for longs, LH for shorts) + 0.5 ATR buffer   |
//|                to avoid being stopped by normal bar noise.       |
//|   Take Profit — nearest Draw on Liquidity → PDH/PDL → lastSwH/L |
//|   Reward:Risk — ≥ 2:1 = A grade, ≥ 1:1 = B grade, < 1:1 = C   |
//|                                                                  |
//| The DrawRRBox function is called from OnChartEvent when the user |
//| clicks a bar. It shows profit/risk zones from that entry level.  |
//+------------------------------------------------------------------+
#ifndef PAM_TRADEMANAGER_MQH
#define PAM_TRADEMANAGER_MQH
#include "Context.mqh"

//+------------------------------------------------------------------+
// TradeManagerEngine_Compute
//   Scans confirmed swings for structural SL, resolves TP from DOL
//   or PD levels, then computes the R:R ratio.
//+------------------------------------------------------------------+
void TradeManagerEngine_Compute(SPAMContext &ctx, double curPrice)
{
   ctx.suggestedSL = 0;
   ctx.suggestedTP = 0;
   ctx.setupRR     = 0;
   ctx.isBullSetup = false;

   if(!ctx.showTradeManager) return;
   if(ctx.trend == TREND_UNDEFINED || ctx.trend == TREND_RANGING) return;
   if(ctx.atr <= 0 || curPrice <= 0) return;

   ctx.isBullSetup = (ctx.trend == TREND_BULLISH);

   // ─── Stop Loss: most recent structural swing ──────────────────
   if(ctx.isBullSetup)
   {
      // Bull setup: SL just below the most recent Higher Low
      for(int i = ctx.nSwings - 1; i >= 0; i--)
      {
         if(ctx.swings[i].label == SE_HL && ctx.swings[i].price < curPrice)
         {
            ctx.suggestedSL = ctx.swings[i].price - ctx.atr * 0.5;
            break;
         }
      }
      // Fallback: PDL provides structural reference
      if(ctx.suggestedSL <= 0 && ctx.pdLow > 0)
         ctx.suggestedSL = ctx.pdLow - ctx.atr * 0.5;
   }
   else
   {
      // Bear setup: SL just above the most recent Lower High
      for(int i = ctx.nSwings - 1; i >= 0; i--)
      {
         if(ctx.swings[i].label == SE_LH && ctx.swings[i].price > curPrice)
         {
            ctx.suggestedSL = ctx.swings[i].price + ctx.atr * 0.5;
            break;
         }
      }
      // Fallback: PDH
      if(ctx.suggestedSL <= 0 && ctx.pdHigh > 0)
         ctx.suggestedSL = ctx.pdHigh + ctx.atr * 0.5;
   }

   if(ctx.suggestedSL <= 0) return;

   // ─── Take Profit: DOL → PD level → last confirmed swing ──────
   if(ctx.isBullSetup)
   {
      if(ctx.dolUp > curPrice)
         ctx.suggestedTP = ctx.dolUp;
      else if(ctx.pdHigh > curPrice)
         ctx.suggestedTP = ctx.pdHigh;
      else if(ctx.lastSwH > curPrice)
         ctx.suggestedTP = ctx.lastSwH;
   }
   else
   {
      if(ctx.dolDown > 0 && ctx.dolDown < curPrice)
         ctx.suggestedTP = ctx.dolDown;
      else if(ctx.pdLow > 0 && ctx.pdLow < curPrice)
         ctx.suggestedTP = ctx.pdLow;
      else if(ctx.lastSwL > 0 && ctx.lastSwL < curPrice)
         ctx.suggestedTP = ctx.lastSwL;
   }

   if(ctx.suggestedTP <= 0) return;

   // ─── Reward : Risk ────────────────────────────────────────────
   double reward = MathAbs(ctx.suggestedTP - curPrice);
   double risk   = MathAbs(curPrice - ctx.suggestedSL);
   if(risk <= 0) return;
   ctx.setupRR = NormalizeDouble(reward / risk, 1);
}

//+------------------------------------------------------------------+
// TradeManagerEngine_Draw
//   Horizontal SL and TP reference lines across the chart.
//+------------------------------------------------------------------+
void TradeManagerEngine_Draw(const SPAMContext &ctx,
                              const datetime   &time[],
                              int               total,
                              const string     &pfx)
{
   if(!ctx.showTradeManager) return;
   if(ctx.suggestedSL <= 0) return;

   int      leftBar  = MathMin(ctx.lookback, total - 1);
   datetime leftTime = time[leftBar];
   datetime nowTime  = time[0];

   // SL line — red dashed, draws on top
   string slNm = pfx + "TMSL";
   ObjectCreate(0, slNm, OBJ_TREND, 0, leftTime, ctx.suggestedSL, nowTime, ctx.suggestedSL);
   ObjectSetInteger(0, slNm, OBJPROP_COLOR,      C'200,60,60');
   ObjectSetInteger(0, slNm, OBJPROP_STYLE,      STYLE_DASH);
   ObjectSetInteger(0, slNm, OBJPROP_WIDTH,      1);
   ObjectSetInteger(0, slNm, OBJPROP_RAY_RIGHT,  true);
   ObjectSetInteger(0, slNm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, slNm, OBJPROP_BACK,       false);

   string slLbl = pfx + "TMSLL";
   ObjectCreate(0, slLbl, OBJ_TEXT, 0, nowTime, ctx.suggestedSL);
   ObjectSetString(0,  slLbl, OBJPROP_TEXT,      "SL");
   ObjectSetInteger(0, slLbl, OBJPROP_COLOR,     C'220,80,80');
   ObjectSetInteger(0, slLbl, OBJPROP_FONTSIZE,  7);
   ObjectSetString(0,  slLbl, OBJPROP_FONT,      "Consolas");
   ObjectSetInteger(0, slLbl, OBJPROP_ANCHOR,    ANCHOR_RIGHT_LOWER);
   ObjectSetInteger(0, slLbl, OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0, slLbl, OBJPROP_BACK,      false);

   if(ctx.suggestedTP <= 0) return;

   // TP line — green dashed, draws on top
   string tpNm = pfx + "TMTP";
   ObjectCreate(0, tpNm, OBJ_TREND, 0, leftTime, ctx.suggestedTP, nowTime, ctx.suggestedTP);
   ObjectSetInteger(0, tpNm, OBJPROP_COLOR,      C'0,200,100');
   ObjectSetInteger(0, tpNm, OBJPROP_STYLE,      STYLE_DASH);
   ObjectSetInteger(0, tpNm, OBJPROP_WIDTH,      1);
   ObjectSetInteger(0, tpNm, OBJPROP_RAY_RIGHT,  true);
   ObjectSetInteger(0, tpNm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, tpNm, OBJPROP_BACK,       false);

   string tpLbl = pfx + "TMTPL";
   ObjectCreate(0, tpLbl, OBJ_TEXT, 0, nowTime, ctx.suggestedTP);
   ObjectSetString(0,  tpLbl, OBJPROP_TEXT,      "TP");
   ObjectSetInteger(0, tpLbl, OBJPROP_COLOR,     C'0,220,120');
   ObjectSetInteger(0, tpLbl, OBJPROP_FONTSIZE,  7);
   ObjectSetString(0,  tpLbl, OBJPROP_FONT,      "Consolas");
   ObjectSetInteger(0, tpLbl, OBJPROP_ANCHOR,    ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0, tpLbl, OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0, tpLbl, OBJPROP_BACK,      false);
}

//+------------------------------------------------------------------+
// TradeManagerEngine_DrawRRBox
//   Click-triggered overlay: filled profit/risk rectangles from the
//   entry bar's close to time[0], plus an R:R grade label.
//   Called from OnChartEvent after the user clicks a bar.
//+------------------------------------------------------------------+
void TradeManagerEngine_DrawRRBox(const SPAMContext &ctx,
                                   double             entryPrice,
                                   datetime           entryTime,
                                   const datetime    &time[],
                                   int                total,
                                   const string      &pfx)
{
   // Remove prior RR box objects before redrawing
   string rr[] = {"RRENT","RRUP","RRDN","RRLBL"};
   for(int k = 0; k < 4; k++) ObjectDelete(0, pfx + rr[k]);

   if(!ctx.showTradeManager) return;
   if(ctx.suggestedSL <= 0 || ctx.suggestedTP <= 0) return;
   if(ctx.setupRR <= 0 || total < 1) return;

   datetime rightTime = time[0];

   // Entry line (white, solid, full-width)
   string entNm = pfx + "RRENT";
   ObjectCreate(0, entNm, OBJ_TREND, 0, entryTime, entryPrice, rightTime, entryPrice);
   ObjectSetInteger(0, entNm, OBJPROP_COLOR,      C'200,200,200');
   ObjectSetInteger(0, entNm, OBJPROP_STYLE,      STYLE_SOLID);
   ObjectSetInteger(0, entNm, OBJPROP_WIDTH,      2);
   ObjectSetInteger(0, entNm, OBJPROP_RAY_RIGHT,  false);
   ObjectSetInteger(0, entNm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, entNm, OBJPROP_BACK,       true);

   // Profit zone: entry → TP (dark green fill, drawn behind bars)
   string upNm = pfx + "RRUP";
   ObjectCreate(0, upNm, OBJ_RECTANGLE, 0, entryTime, entryPrice, rightTime, ctx.suggestedTP);
   ObjectSetInteger(0, upNm, OBJPROP_COLOR,      C'0,120,60');
   ObjectSetInteger(0, upNm, OBJPROP_STYLE,      ctx.outlineMode ? STYLE_DOT : STYLE_SOLID);
   ObjectSetInteger(0, upNm, OBJPROP_FILL,       !ctx.outlineMode);
   ObjectSetInteger(0, upNm, OBJPROP_WIDTH,      1);
   ObjectSetInteger(0, upNm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, upNm, OBJPROP_BACK,       true);

   // Risk zone: entry → SL (dark red fill, drawn behind bars)
   string dnNm = pfx + "RRDN";
   ObjectCreate(0, dnNm, OBJ_RECTANGLE, 0, entryTime, entryPrice, rightTime, ctx.suggestedSL);
   ObjectSetInteger(0, dnNm, OBJPROP_COLOR,      C'120,0,0');
   ObjectSetInteger(0, dnNm, OBJPROP_STYLE,      ctx.outlineMode ? STYLE_DOT : STYLE_SOLID);
   ObjectSetInteger(0, dnNm, OBJPROP_FILL,       !ctx.outlineMode);
   ObjectSetInteger(0, dnNm, OBJPROP_WIDTH,      1);
   ObjectSetInteger(0, dnNm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, dnNm, OBJPROP_BACK,       true);

   // Grade badge: A+ ≥ 3:1, A ≥ 2:1, B ≥ 1:1, C < 1:1
   string grade = (ctx.setupRR >= 3.0) ? "A+" : (ctx.setupRR >= 2.0) ? "A" : (ctx.setupRR >= 1.0) ? "B" : "C";
   color  gradeCol = (ctx.setupRR >= 2.0) ? C'0,220,120' : (ctx.setupRR >= 1.0) ? C'220,180,0' : C'200,60,60';

   string lblTxt = StringFormat("Entry %s  SL %s  TP %s  RR %.1f:1 [%s]",
                                 DoubleToString(entryPrice,       _Digits),
                                 DoubleToString(ctx.suggestedSL,  _Digits),
                                 DoubleToString(ctx.suggestedTP,  _Digits),
                                 ctx.setupRR, grade);
   string lblNm = pfx + "RRLBL";
   ObjectCreate(0, lblNm, OBJ_TEXT, 0, entryTime, entryPrice);
   ObjectSetString(0,  lblNm, OBJPROP_TEXT,      lblTxt);
   ObjectSetInteger(0, lblNm, OBJPROP_COLOR,     gradeCol);
   ObjectSetInteger(0, lblNm, OBJPROP_FONTSIZE,  7);
   ObjectSetString(0,  lblNm, OBJPROP_FONT,      "Consolas");
   ObjectSetInteger(0, lblNm, OBJPROP_ANCHOR,    ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0, lblNm, OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0, lblNm, OBJPROP_BACK,      false);
}

//+------------------------------------------------------------------+
// TradeManagerEngine_DashString
//   Dashboard row: directional bias + SL + TP + R:R grade.
//+------------------------------------------------------------------+
string TradeManagerEngine_DashString(const SPAMContext &ctx)
{
   if(!ctx.showTradeManager)
      return "  Trade Mgr  off";

   if(ctx.suggestedSL <= 0)
      return "  Trade Mgr  awaiting structure";

   string dir = ctx.isBullSetup ? "L" : "S";

   if(ctx.suggestedTP <= 0)
      return StringFormat("  Trade Mgr  [%s] SL %s  no target",
                          dir, DoubleToString(ctx.suggestedSL, _Digits));

   string grade = (ctx.setupRR >= 3.0) ? " A+" : (ctx.setupRR >= 2.0) ? " A" : (ctx.setupRR >= 1.0) ? " B" : " C";
   return StringFormat("  Trade Mgr  [%s] SL %s  TP %s  RR %.1f%s",
                       dir,
                       DoubleToString(ctx.suggestedSL, _Digits),
                       DoubleToString(ctx.suggestedTP, _Digits),
                       ctx.setupRR, grade);
}

#endif // PAM_TRADEMANAGER_MQH
