//+------------------------------------------------------------------+
//| PAM/ReplayEngine.mqh  —  Historical learning mode               |
//|                                                                  |
//| When the user clicks on any historical bar, this engine:         |
//|  1. Identifies which bar was clicked                             |
//|  2. Finds the nearest swing, liquidity level, and zone          |
//|  3. Classifies the clicked candle itself                         |
//|  4. Generates a context-aware educational explanation           |
//|  5. Displays a floating analysis panel on the chart             |
//|                                                                  |
//| IMPORTANT: This uses already-computed ctx state (not a full     |
//| historical re-run). This is acceptable for MVP because the      |
//| swing sequence is available for ALL historical bars in the scan.|
//+------------------------------------------------------------------+
#ifndef PAM_REPLAY_MQH
#define PAM_REPLAY_MQH
#include "Context.mqh"

// Replay panel geometry
#define RP_X    8
#define RP_Y    348
#define RP_W    310
#define RP_H    185

//+------------------------------------------------------------------+
// Find which bar (series index) corresponds to a click timestamp
//+------------------------------------------------------------------+
int ReplayEngine_FindBar(datetime clickTime, const datetime &time[], int total)
{
   // time[] is series (index 0 = newest), so search forward
   for(int i = 0; i < total; i++)
   {
      if(time[i] <= clickTime) return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
// Find the nearest swing in ctx.swings[] to a given bar index
//+------------------------------------------------------------------+
int ReplayEngine_NearestSwing(const SPAMContext &ctx, int targetBar)
{
   if(ctx.nSwings == 0) return -1;
   int best  = 0;
   int bestD = MathAbs(ctx.swings[0].bar - targetBar);
   for(int i = 1; i < ctx.nSwings; i++)
   {
      int d = MathAbs(ctx.swings[i].bar - targetBar);
      if(d < bestD) { bestD = d; best = i; }
   }
   return best;
}

//+------------------------------------------------------------------+
// Find nearest liquidity level in price to a given price level
//+------------------------------------------------------------------+
int ReplayEngine_NearestLiq(const SPAMContext &ctx, double price)
{
   if(ctx.nLiq == 0) return -1;
   int    best  = 0;
   double bestD = MathAbs(ctx.liq[0].price - price);
   for(int i = 1; i < ctx.nLiq; i++)
   {
      double d = MathAbs(ctx.liq[i].price - price);
      if(d < bestD) { bestD = d; best = i; }
   }
   return best;
}

//+------------------------------------------------------------------+
// Build the replay narrative for a specific bar
//+------------------------------------------------------------------+
string ReplayEngine_BuildExplanation(const SPAMContext &ctx,
                                      int                clickBar,
                                      const double      &open[],
                                      const double      &high[],
                                      const double      &low[],
                                      const double      &close[],
                                      const double      &atr[],
                                      EMode              mode)
{
   if(clickBar < 0 || clickBar >= PAM_MAX_CANDLES) return "";

   // Classify the clicked candle
   SCandle sc = CandleEngine_ClassifyOne(clickBar, 0,
                                          open[clickBar], high[clickBar],
                                          low[clickBar], close[clickBar],
                                          atr[clickBar], ctx.dispThresh, mode);

   // Find the structure context at this bar
   int swingIdx = ReplayEngine_NearestSwing(ctx, clickBar);
   int liqIdx   = ReplayEngine_NearestLiq(ctx, (high[clickBar] + low[clickBar]) / 2.0);

   string explanation = "";

   // ─── Candle ─────────────────────────────────────────────────
   string candleLine = "Candle: " + CandleEngine_TypeString(sc.type);
   if(sc.rangeVsAtr > 0)
      candleLine += " (" + DoubleToString(sc.rangeVsAtr, 1) + "x ATR)";
   explanation += candleLine;

   // ─── Swing context ────────────────────────────────────────────
   if(swingIdx >= 0)
   {
      SSwing sw = ctx.swings[swingIdx];
      int    distBars = MathAbs(sw.bar - clickBar);
      string swLabel = "";
      switch(sw.label)
      {
         case SE_HH:       swLabel = "HH"; break;
         case SE_HL:       swLabel = "HL"; break;
         case SE_LH:       swLabel = "LH"; break;
         case SE_LL:       swLabel = "LL"; break;
         case SE_BOS_BULL: swLabel = "BOS▲"; break;
         case SE_BOS_BEAR: swLabel = "BOS▼"; break;
         case SE_CHOCH_BULL: swLabel = "CHoCH▲"; break;
         case SE_CHOCH_BEAR: swLabel = "CHoCH▼"; break;
         case SE_MSS_BULL: swLabel = "MSS▲"; break;
         case SE_MSS_BEAR: swLabel = "MSS▼"; break;
         default:          swLabel = "swing"; break;
      }
      explanation += " | Nearest swing: " + swLabel + " " +
                     IntegerToString(distBars) + " bars " +
                     (distBars == 0 ? "here" : (sw.bar > clickBar ? "later" : "ago"));
   }

   // ─── Liquidity context ────────────────────────────────────────
   if(liqIdx >= 0)
   {
      SLiqLevel lv = ctx.liq[liqIdx];
      string liqType = (lv.type == LIQ_BUY_SIDE) ? "buy-side" : "sell-side";
      string sweptTxt = lv.swept ? " (swept)" : " (intact)";
      explanation += " | " + liqType + " liquidity @ " +
                     DoubleToString(lv.price, _Digits) + sweptTxt;
   }

   // ─── Educational interpretation (mode-aware) ──────────────────
   string interp = "";
   switch(sc.type)
   {
      case CANDLE_DISPLACEMENT_BULL:
         switch(mode)
         {
            case MODE_BEGINNER:
               interp = "This large bullish candle shows strong buying. It moved fast, "
                        "suggesting buyers were very aggressive here.";
               break;
            case MODE_ADVANCED:
               interp = "Bullish displacement: high momentum candle suggesting institutional "
                        "buying. This bar may have broken prior structure.";
               break;
            case MODE_INSTITUTIONAL:
               interp = "Institutional displacement: high-velocity order flow absorbed "
                        "available sell-side liquidity and displaced price. The prior bearish "
                        "candle is now a bullish order block — monitor for retracement to that zone.";
               break;
         }
         break;
      case CANDLE_DISPLACEMENT_BEAR:
         switch(mode)
         {
            case MODE_BEGINNER:
               interp = "This large bearish candle shows strong selling. Sellers were "
                        "very aggressive — price dropped fast.";
               break;
            case MODE_ADVANCED:
               interp = "Bearish displacement: institutional selling pressure. "
                        "Check if this broke prior structure (BOS or CHoCH).";
               break;
            case MODE_INSTITUTIONAL:
               interp = "Bearish institutional displacement: large sell-side order flow "
                        "absorbed bids and displaced price. Look for the last bullish candle "
                        "before this move — that is a bearish order block for future shorts.";
               break;
         }
         break;
      case CANDLE_EXHAUSTION_BULL:
         switch(mode)
         {
            case MODE_BEGINNER:
               interp = "Buyers pushed price up but sellers rejected it — the long upper wick "
                        "shows buyers lost the fight at this level.";
               break;
            case MODE_ADVANCED:
               interp = "Bullish exhaustion wick: strong rejection at a potential supply zone. "
                        "Could signal reversal or corrective pullback.";
               break;
            case MODE_INSTITUTIONAL:
               interp = "Supply absorption: institutions distributed longs into retail buy flow. "
                        "The wick represents stop-hunt of buy-side liquidity. Potential CHoCH if "
                        "next bar closes below the body of this candle.";
               break;
         }
         break;
      case CANDLE_EXHAUSTION_BEAR:
         switch(mode)
         {
            case MODE_BEGINNER:
               interp = "Sellers pushed price down but buyers stepped in hard — the long lower "
                        "wick shows sellers failed at this level.";
               break;
            case MODE_ADVANCED:
               interp = "Bearish exhaustion wick: strong demand rejection. "
                        "Possible reversal signal if combined with structural support.";
               break;
            case MODE_INSTITUTIONAL:
               interp = "Demand absorption: institutions bought into retail sell pressure. "
                        "Wick represents stop-hunt of sell-side liquidity. Potential CHoCH if "
                        "next bar closes above the body of this candle.";
               break;
         }
         break;
      case CANDLE_INDECISION:
         switch(mode)
         {
            case MODE_BEGINNER:
               interp = "Neither buyers nor sellers dominated here — the market was undecided. "
                        "Wait for direction on the next candle.";
               break;
            case MODE_ADVANCED:
               interp = "Equilibrium candle: order flow balanced. Key: WHERE this formed. "
                        "Doji at resistance = rejection signal. Doji mid-range = noise.";
               break;
            case MODE_INSTITUTIONAL:
               interp = "Order flow equilibrium: neither side committed. If at a known "
                        "institutional zone (OB/FVG), this represents a potential absorption "
                        "before directional commitment.";
               break;
         }
         break;
      case CANDLE_HAMMER:
         switch(mode)
         {
            case MODE_BEGINNER:
               interp = "Sellers pushed price down but buyers aggressively stepped in. "
                        "This 'hammer' shape often signals a reversal upward.";
               break;
            case MODE_ADVANCED:
               interp = "Hammer / pin bar: strong demand wick. Most meaningful when it forms "
                        "at a structural low, OB, or after a liquidity sweep.";
               break;
            case MODE_INSTITUTIONAL:
               interp = "Demand spike: stop hunt of sell-side liquidity with immediate "
                        "institutional absorption. High probability reversal if combined "
                        "with HTF bullish bias and OB/FVG confluence.";
               break;
         }
         break;
      case CANDLE_SHOOTING_STAR:
         switch(mode)
         {
            case MODE_BEGINNER:
               interp = "Buyers pushed price up but sellers stepped in hard. "
                        "This 'shooting star' shape often signals a drop coming.";
               break;
            case MODE_ADVANCED:
               interp = "Shooting star / pin bar: strong supply wick. Most meaningful at "
                        "structural highs, bearish OB, or after a buy-side liquidity sweep.";
               break;
            case MODE_INSTITUTIONAL:
               interp = "Supply spike: stop hunt of buy-side liquidity with institutional "
                        "distribution. High probability reversal with HTF bearish bias "
                        "and OB/FVG confluence at this level.";
               break;
         }
         break;
      default:
         switch(mode)
         {
            case MODE_BEGINNER:      interp = "This bar shows normal market activity — no extreme signals."; break;
            case MODE_ADVANCED:      interp = "Neutral candle — context from surrounding structure is primary."; break;
            case MODE_INSTITUTIONAL: interp = "No strong order flow imbalance on this bar — structure context dominant."; break;
         }
         break;
   }
   explanation += " || " + interp;
   return explanation;
}

//+------------------------------------------------------------------+
// UIEngine label helpers (forward declared)
//+------------------------------------------------------------------+
void UI_MakeLabel(string name, int x, int y, int sz);
void UI_SetLabel(string name, string text, color c);
string CandleEngine_TypeString(ECandleType t);
SCandle CandleEngine_ClassifyOne(int bar, datetime t, double o, double h, double l, double cls, double atr, double disp, EMode mode);

//+------------------------------------------------------------------+
// ReplayEngine_CreatePanel — one-time creation of replay panel
//+------------------------------------------------------------------+
void ReplayEngine_CreatePanel(const string &pfx)
{
   string bg = pfx + "REPLAY_BG";
   ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bg, OBJPROP_CORNER,      CORNER_LEFT_UPPER);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE,   RP_X);
   ObjectSetInteger(0, bg, OBJPROP_YDISTANCE,   RP_Y);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE,       RP_W);
   ObjectSetInteger(0, bg, OBJPROP_YSIZE,       RP_H);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR,     C'5,12,5');
   ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bg, OBJPROP_COLOR,       C'0,80,40');
   ObjectSetInteger(0, bg, OBJPROP_SELECTABLE,  false);
   ObjectSetInteger(0, bg, OBJPROP_BACK,        false);
   ObjectSetInteger(0, bg, OBJPROP_ZORDER,      1);

   int dx = RP_X + 12;
   int dy = RP_Y + 10;
   UI_MakeLabel(pfx + "REPLAY_TITLE", dx, dy,      9);
   UI_MakeLabel(pfx + "REPLAY_L1",   dx, dy += 18, 8);
   UI_MakeLabel(pfx + "REPLAY_L2",   dx, dy += 14, 8);
   UI_MakeLabel(pfx + "REPLAY_L3",   dx, dy += 14, 8);
   UI_MakeLabel(pfx + "REPLAY_L4",   dx, dy += 14, 8);
   UI_MakeLabel(pfx + "REPLAY_L5",   dx, dy += 14, 8);
   UI_MakeLabel(pfx + "REPLAY_N1",   dx, dy += 18, 7);
   UI_MakeLabel(pfx + "REPLAY_N2",   dx, dy += 12, 7);
   UI_MakeLabel(pfx + "REPLAY_N3",   dx, dy += 12, 7);

   ObjectSetString(0,  pfx + "REPLAY_TITLE", OBJPROP_TEXT,  "  HISTORICAL ANALYSIS  [click any bar]");
   ObjectSetInteger(0, pfx + "REPLAY_TITLE", OBJPROP_COLOR, C'0,200,100');
}

//+------------------------------------------------------------------+
// ReplayEngine_ShowAnalysis
//   Called from OnChartEvent when user clicks a bar.
//+------------------------------------------------------------------+
void ReplayEngine_ShowAnalysis(const SPAMContext &ctx,
                                int               clickBar,
                                datetime          clickTime,
                                const double      &open[],
                                const double      &high[],
                                const double      &low[],
                                const double      &close[],
                                const double      &atr[],
                                const string      &pfx)
{
   if(clickBar < 0 || clickBar >= MathMin(PAM_MAX_CANDLES, ArraySize(open)))
   {
      UI_SetLabel(pfx + "REPLAY_L1", "  Click on a visible bar to analyze it.", clrSilver);
      UI_SetLabel(pfx + "REPLAY_L2", "", clrSilver);
      UI_SetLabel(pfx + "REPLAY_L3", "", clrSilver);
      UI_SetLabel(pfx + "REPLAY_L4", "", clrSilver);
      UI_SetLabel(pfx + "REPLAY_L5", "", clrSilver);
      UI_SetLabel(pfx + "REPLAY_N1", "", clrSilver);
      UI_SetLabel(pfx + "REPLAY_N2", "", clrSilver);
      UI_SetLabel(pfx + "REPLAY_N3", "", clrSilver);
      return;
   }

   string hdr = "  BAR: " + IntegerToString(clickBar) + " bars ago  │  " +
                TimeToString(clickTime, TIME_DATE | TIME_MINUTES);
   UI_SetLabel(pfx + "REPLAY_TITLE",
               "  HISTORICAL ANALYSIS  " + hdr, C'0,200,100');

   // Candle data
   SCandle sc = CandleEngine_ClassifyOne(clickBar, clickTime,
                                          open[clickBar], high[clickBar],
                                          low[clickBar], close[clickBar],
                                          atr[clickBar], ctx.dispThresh, ctx.mode);

   string l1 = StringFormat("  Candle  %s   %.1fx ATR   Body:%d%%   Wick↑:%d%%  Wick↓:%d%%",
      CandleEngine_TypeString(sc.type),
      sc.rangeVsAtr,
      (int)(sc.bodyRatio * 100),
      (int)(sc.upperWickRatio * 100),
      (int)(sc.lowerWickRatio * 100));

   // Nearest swing
   int swIdx = ReplayEngine_NearestSwing(ctx, clickBar);
   string l2 = "";
   if(swIdx >= 0)
   {
      SSwing sw = ctx.swings[swIdx];
      string slbl;
      switch(sw.label)
      {
         case SE_HH: slbl="HH"; break; case SE_HL: slbl="HL"; break;
         case SE_LH: slbl="LH"; break; case SE_LL: slbl="LL"; break;
         case SE_BOS_BULL: slbl="BOS▲"; break; case SE_BOS_BEAR: slbl="BOS▼"; break;
         case SE_CHOCH_BULL: slbl="CHoCH▲"; break; case SE_CHOCH_BEAR: slbl="CHoCH▼"; break;
         case SE_MSS_BULL: slbl="MSS▲"; break; case SE_MSS_BEAR: slbl="MSS▼"; break;
         default: slbl="Swing"; break;
      }
      if(sw.isMSS)  slbl += "+MSS";
      if(sw.isBOS)  slbl += "+BOS";
      l2 = StringFormat("  Nearest swing: %s @ %s  (%d bars away)",
           slbl, DoubleToString(sw.price, _Digits), MathAbs(sw.bar - clickBar));
   }

   // Liquidity context
   int liqIdx = ReplayEngine_NearestLiq(ctx, (high[clickBar] + low[clickBar]) / 2.0);
   string l3 = "";
   if(liqIdx >= 0)
   {
      SLiqLevel lv = ctx.liq[liqIdx];
      string lType = (lv.type == LIQ_BUY_SIDE) ? "Buy-side (stops above)" : "Sell-side (stops below)";
      l3 = StringFormat("  Liquidity: %s @ %s  [%s]",
           lType, DoubleToString(lv.price, _Digits), lv.swept ? "SWEPT" : "intact");
   }

   // Overall structure context at click bar
   string l4 = "  Structure: " + (ctx.trend == TREND_BULLISH ? "BULLISH ▲ (HH/HL)" :
                                   ctx.trend == TREND_BEARISH ? "BEARISH ▼ (LH/LL)" :
                                   ctx.trend == TREND_RANGING ? "RANGING ~" : "Undefined");
   string l5 = "  Phase: " + PhaseWord(ctx.phase) + "   HTF: " +
               (ctx.htfTrend == TREND_BULLISH ? "BULLISH ▲" :
                ctx.htfTrend == TREND_BEARISH ? "BEARISH ▼" : "---");

   // Educational interpretation — split into lines
   string fullInterp = ReplayEngine_BuildExplanation(ctx, clickBar,
                        open, high, low, close, atr, ctx.mode);

   // Extract just the "||" part (after the bar stats)
   string narPart = fullInterp;
   int sepPos = StringFind(narPart, "||");
   if(sepPos >= 0) { narPart = StringSubstr(narPart, sepPos + 2); StringTrimLeft(narPart); }

   // Split narration into 3 display lines
   string nlines[3]; nlines[0] = nlines[1] = nlines[2] = "";
   int pos = 0, maxLen = 46;
   for(int i = 0; i < 3 && pos < StringLen(narPart); i++)
   {
      int end = pos + maxLen;
      if(end >= StringLen(narPart)) end = StringLen(narPart);
      else while(end > pos && StringGetCharacter(narPart, end) != 32) end--;
      if(end == pos) end = pos + maxLen;
      nlines[i] = "  " + StringSubstr(narPart, pos, end - pos);
      pos = end + 1;
   }

   UI_SetLabel(pfx + "REPLAY_L1", l1, C'200,200,255');
   UI_SetLabel(pfx + "REPLAY_L2", l2, C'200,220,200');
   UI_SetLabel(pfx + "REPLAY_L3", l3, C'220,200,100');
   UI_SetLabel(pfx + "REPLAY_L4", l4, C'150,200,255');
   UI_SetLabel(pfx + "REPLAY_L5", l5, C'150,200,255');
   UI_SetLabel(pfx + "REPLAY_N1", nlines[0], C'180,220,180');
   UI_SetLabel(pfx + "REPLAY_N2", nlines[1], C'160,200,160');
   UI_SetLabel(pfx + "REPLAY_N3", nlines[2], C'140,180,140');
}

string PhaseWord(EPhase p);

#endif // PAM_REPLAY_MQH
