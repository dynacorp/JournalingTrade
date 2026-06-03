//+------------------------------------------------------------------+
//|                                      PriceActionMentor.mq5      |
//|                                                                  |
//|  PRICE ACTION MENTOR AI  v1.0                                   |
//|  A live chart teacher for institutional price action reading.   |
//|                                                                  |
//|  Teaches:                                                        |
//|   • Market structure  (HH HL LH LL  BOS CHoCH MSS)            |
//|   • Liquidity pools   (EQH EQL sweeps stop-hunts)              |
//|   • Smart zones       (OB FVG Breaker blocks)                  |
//|   • Candle psychology (displacement exhaustion indecision)      |
//|   • Market phase      (accumulation manipulation expansion …)   |
//|   • Multi-TF bias     (HTF alignment / divergence)             |
//|   • Historical replay (click any bar for full analysis)         |
//|                                                                  |
//|  NOT a prediction tool. NOT a signal generator.                 |
//|  100% non-repainting — all pivots confirmed before drawn.       |
//+------------------------------------------------------------------+
#property copyright   "TradeMind — Price Action Mentor AI"
#property version     "1.50"
#property strict
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//--- Include all engine modules
#include "PAM/Context.mqh"
#include "PAM/StructureEngine.mqh"
#include "PAM/LiquidityEngine.mqh"
#include "PAM/CandleEngine.mqh"
#include "PAM/ZoneEngine.mqh"
#include "PAM/PremDiscEngine.mqh"
#include "PAM/ScoringEngine.mqh"
#include "PAM/MTFEngine.mqh"
#include "PAM/UIEngine.mqh"
#include "PAM/SessionEngine.mqh"
#include "PAM/KillZoneEngine.mqh"
#include "PAM/DOLEngine.mqh"
#include "PAM/DailyBiasEngine.mqh"
#include "PAM/SetupEngine.mqh"
#include "PAM/TradeManagerEngine.mqh"
#include "PAM/ReplayEngine.mqh"

//+------------------------------------------------------------------+
//| Input groups                                                      |
//+------------------------------------------------------------------+
input group "─── Education Mode ──────────────────────────────────────"
input EMode InpMode = MODE_ADVANCED;       // Education depth

input group "─── Market Structure ────────────────────────────────────"
input int   InpPivotStr     = 5;           // Pivot strength (bars each side)
input int   InpLookback     = 300;         // Lookback bars
input bool  InpShowInternal = false;       // Show internal (micro) structure
input bool  InpShowBOS      = true;        // Show BOS labels
input bool  InpShowCHoCH    = true;        // Show CHoCH / MSS labels

input group "─── Sessions ────────────────────────────────────────────"
input bool InpShowSessions  = true;        // Show session boxes
input bool InpShowAsian     = true;        // Asian session (22:00–07:00)
input bool InpShowLondon    = true;        // London session (07:00–16:00)
input bool InpShowNY        = true;        // New York session (12:00–21:00)
input bool InpShowOverlap   = true;        // London/NY overlap (12:00–16:00)
input int  InpAsianOpenH    = 22;          // Asian open  (broker hour)
input int  InpAsianCloseH   = 7;           // Asian close (broker hour)
input int  InpLondonOpenH   = 7;           // London open (broker hour)
input int  InpLondonCloseH  = 16;          // London close
input int  InpNYOpenH       = 12;          // NY open
input int  InpNYCloseH      = 21;          // NY close
input int  InpSessionDays   = 3;           // Calendar days to shade

input group "─── Premium / Discount ──────────────────────────────────"
input bool  InpShowPremDisc = true;        // Show Premium/Discount grid
input bool  InpShowFibs     = true;        // Show Fibonacci OTE levels (23.6–78.6%)

input group "─── Kill Zones ──────────────────────────────────────────"
input bool  InpShowKillZones = true;       // Show ICT kill zone boxes
input bool  InpShowLondonKZ  = true;       // London Open KZ  (07:00–10:00)
input bool  InpShowNYAMKZ    = true;       // NY Open KZ      (12:00–15:00)
input bool  InpShowNYPMKZ    = false;      // NY PM KZ        (19:00–21:00)
input bool  InpShowAsianKZ   = false;      // Asian KZ        (20:00–23:00)
input int   InpKZDays        = 3;          // Calendar days to draw

input group "─── Draw on Liquidity ───────────────────────────────────"
input bool  InpShowDOL       = true;       // Show Draw on Liquidity targets

input group "─── Daily & Weekly Bias ─────────────────────────────────"
input bool  InpShowDailyBias  = true;      // Enable daily/weekly reference levels
input bool  InpShowPDLevels   = true;      // Draw PDH / PDL / PDC / PDM lines
input bool  InpShowWeeklyOpen = true;      // Draw weekly open line

input group "─── Setup Patterns ──────────────────────────────────────"
input bool  InpShowJudas       = true;     // Judas Swing detection (KZ stop-hunt)
input bool  InpShowSilverBullet= true;     // Silver Bullet time windows
input bool  InpShowCISD        = true;     // Change in State of Delivery marker
input bool  InpShowOTE         = true;     // Optimal Trade Entry zone (61.8-78.6%)
input int   InpSBAMOpenH       = 10;       // Silver Bullet AM open  (broker hour)
input int   InpSBAMCloseH      = 11;       // Silver Bullet AM close
input int   InpSBPMOpenH       = 14;       // Silver Bullet PM open
input int   InpSBPMCloseH      = 15;       // Silver Bullet PM close

input group "─── Trade Management ────────────────────────────────────"
input bool  InpShowTradeManager = true;    // Show SL / TP / R:R overlay

input group "─── Liquidity ───────────────────────────────────────────"
input bool   InpShowLiq     = true;        // Show liquidity levels
input bool   InpShowSweeps  = true;        // Show swept levels
input double InpEqTol       = 0.20;        // ATR tolerance for equal levels

input group "─── Smart Zones ─────────────────────────────────────────"
input bool   InpShowOB      = true;        // Show order blocks
input bool   InpShowFVG     = true;        // Show fair value gaps
input bool   InpShowBreaker = true;        // Show breaker blocks
input double InpMinFvgAtr   = 0.25;        // Minimum FVG size (ATR units)
input double InpDispThresh  = 1.0;         // Displacement: body >= X * ATR

input group "─── Candle Psychology ───────────────────────────────────"
input bool   InpShowCandles = true;        // Show candle classification labels

input group "─── Multi-Timeframe ─────────────────────────────────────"
input bool             InpUseMTF = true;       // Enable HTF context
input ENUM_TIMEFRAMES  InpHTF    = PERIOD_H1;  // Higher timeframe

input group "─── Dashboard ───────────────────────────────────────────"
input bool  InpShowDash    = true;         // Show information dashboard
input bool  InpShowReplay  = true;         // Enable click-to-analyze (replay mode)
input bool  InpOutlineMode = false;        // Outline mode: all boxes become dotted outlines (less clutter)

input group "─── Color Scheme ────────────────────────────────────────"
input color InpBullCol    = C'0,180,110';        // Bullish structure color
input color InpBearCol    = C'210,60,60';         // Bearish structure color
input color InpNeutCol    = C'140,140,200';       // Neutral / info color
input color InpLiqCol     = C'220,180,0';         // Liquidity level color
input color InpFvgBullCol = C'0,60,30';           // Bull FVG fill
input color InpFvgBearCol = C'60,15,15';          // Bear FVG fill
input color InpObBullCol  = C'0,60,180';          // Bull OB border
input color InpObBearCol  = C'140,0,140';         // Bear OB border

//+------------------------------------------------------------------+
//| Globals                                                           |
//+------------------------------------------------------------------+
SPAMContext g_ctx;
string      g_pfx = "PAM_";

// Stored price arrays for replay engine (last PAM_MAX_CANDLES bars)
double   g_open[];
double   g_high[];
double   g_low[];
double   g_close[];
datetime g_time[];
double   g_atr[];
int      g_storedBars = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME, "Price Action Mentor AI");

   // ─── Populate context configuration from inputs ───────────────
   g_ctx.mode        = InpMode;
   g_ctx.pivStr      = InpPivotStr;
   g_ctx.lookback    = InpLookback;
   g_ctx.htf         = InpHTF;
   g_ctx.showInternal= InpShowInternal;
   g_ctx.showBOS     = InpShowBOS;
   g_ctx.showCHoCH   = InpShowCHoCH;
   g_ctx.showLiq     = InpShowLiq;
   g_ctx.showSweeps  = InpShowSweeps;
   g_ctx.showOB      = InpShowOB;
   g_ctx.showFVG     = InpShowFVG;
   g_ctx.showBreaker = InpShowBreaker;
   g_ctx.showCandles = InpShowCandles;
   g_ctx.eqTol       = InpEqTol;
   g_ctx.minFvgAtr   = InpMinFvgAtr;
   g_ctx.dispThresh  = InpDispThresh;
   g_ctx.bullCol     = InpBullCol;
   g_ctx.bearCol     = InpBearCol;
   g_ctx.neutCol     = InpNeutCol;
   g_ctx.liqCol      = InpLiqCol;
   g_ctx.fvgBullCol  = InpFvgBullCol;
   g_ctx.fvgBearCol  = InpFvgBearCol;
   g_ctx.obBullCol   = InpObBullCol;
   g_ctx.obBearCol   = InpObBearCol;
   g_ctx.outlineMode = InpOutlineMode;
   g_ctx.nSwings     = 0;
   g_ctx.nLiq        = 0;
   g_ctx.nZones      = 0;
   g_ctx.nCandles    = 0;
   g_ctx.nISwings    = 0;

   // v1.1 — Sessions
   g_ctx.showSessions  = InpShowSessions;
   g_ctx.showAsian     = InpShowAsian;
   g_ctx.showLondon    = InpShowLondon;
   g_ctx.showNY        = InpShowNY;
   g_ctx.showOverlap   = InpShowOverlap;
   g_ctx.asianOpenH    = InpAsianOpenH;
   g_ctx.asianCloseH   = InpAsianCloseH;
   g_ctx.londonOpenH   = InpLondonOpenH;
   g_ctx.londonCloseH  = InpLondonCloseH;
   g_ctx.nyOpenH       = InpNYOpenH;
   g_ctx.nyCloseH      = InpNYCloseH;
   g_ctx.sessDays      = InpSessionDays;

   // v1.1 — Premium / Discount
   g_ctx.showPremDisc  = InpShowPremDisc;
   g_ctx.equilPrice    = 0;
   g_ctx.premDiscPct   = 50;

   // v1.2 — Kill Zones
   g_ctx.showKillZones = InpShowKillZones;
   g_ctx.showLondonKZ  = InpShowLondonKZ;
   g_ctx.showNYAMKZ    = InpShowNYAMKZ;
   g_ctx.showNYPMKZ    = InpShowNYPMKZ;
   g_ctx.showAsianKZ   = InpShowAsianKZ;
   g_ctx.kzDays        = InpKZDays;

   // v1.2 — Draw on Liquidity
   g_ctx.showDOL  = InpShowDOL;
   g_ctx.dolUp    = 0;
   g_ctx.dolDown  = 0;

   // v1.3 — Daily / Weekly Bias
   g_ctx.showDailyBias  = InpShowDailyBias;
   g_ctx.showPDLevels   = InpShowPDLevels;
   g_ctx.showWeeklyOpen = InpShowWeeklyOpen;
   g_ctx.pdHigh         = 0;
   g_ctx.pdLow          = 0;
   g_ctx.pdClose        = 0;
   g_ctx.pdMid          = 0;
   g_ctx.weeklyOpen     = 0;
   g_ctx.dailyBias      = TREND_UNDEFINED;
   g_ctx.weeklyBias     = TREND_UNDEFINED;

   // v1.4 — Setup Patterns
   g_ctx.showJudas        = InpShowJudas;
   g_ctx.showSilverBullet = InpShowSilverBullet;
   g_ctx.showCISD         = InpShowCISD;
   g_ctx.showOTE          = InpShowOTE;
   g_ctx.sbAMOpenH        = InpSBAMOpenH;
   g_ctx.sbAMCloseH       = InpSBAMCloseH;
   g_ctx.sbPMOpenH        = InpSBPMOpenH;
   g_ctx.sbPMCloseH       = InpSBPMCloseH;
   g_ctx.activeSetup      = "";

   // v1.5 — Trade Management
   g_ctx.showTradeManager = InpShowTradeManager;
   g_ctx.suggestedSL      = 0;
   g_ctx.suggestedTP      = 0;
   g_ctx.setupRR          = 0;
   g_ctx.isBullSetup      = false;

   // ─── ATR handle ──────────────────────────────────────────────
   g_ctx.atrHandle = iATR(_Symbol, _Period, 14);
   if(g_ctx.atrHandle == INVALID_HANDLE)
   {
      Print("PAM: ATR handle failed");
      return INIT_FAILED;
   }

   // ─── MTF init ────────────────────────────────────────────────
   if(InpUseMTF && !MTFEngine_Init(g_ctx))
      Print("PAM: HTF ATR handle failed — MTF disabled");

   // ─── Pre-size replay buffers ──────────────────────────────────
   ArraySetAsSeries(g_open,  true);
   ArraySetAsSeries(g_high,  true);
   ArraySetAsSeries(g_low,   true);
   ArraySetAsSeries(g_close, true);
   ArraySetAsSeries(g_time,  true);
   ArraySetAsSeries(g_atr,   true);

   // ─── Dashboard creation ───────────────────────────────────────
   if(InpShowDash)
   {
      UIEngine_CreateDash(g_pfx);
      if(InpShowReplay) ReplayEngine_CreatePanel(g_pfx);
   }

   ChartRedraw(0);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_ctx.atrHandle    != INVALID_HANDLE) IndicatorRelease(g_ctx.atrHandle);
   if(g_ctx.htfAtrHandle != INVALID_HANDLE) IndicatorRelease(g_ctx.htfAtrHandle);
   UIEngine_DeleteAllObjects(g_pfx);
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
int OnCalculate(const int      rates_total,
                const int      prev_calculated,
                const datetime &time[],
                const double   &open[],
                const double   &high[],
                const double   &low[],
                const double   &close[],
                const long     &tick_volume[],
                const long     &volume[],
                const int      &spread[])
{
   if(rates_total < 20) return 0;

   // Orient all arrays as series (index 0 = newest bar)
   ArraySetAsSeries(open,  true);
   ArraySetAsSeries(high,  true);
   ArraySetAsSeries(low,   true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(time,  true);

   // Get ATR values
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(g_ctx.atrHandle, 0, 0, rates_total, atr) <= 0)
      return prev_calculated;
   g_ctx.atr = atr[0];

   // ─── Trigger: only full recalc on new confirmed bar ───────────
   bool newBar = (prev_calculated == 0 || prev_calculated < rates_total);
   if(!newBar) return rates_total;

   // ─── Reset engine outputs ────────────────────────────────────
   g_ctx.nSwings    = 0;
   g_ctx.nISwings   = 0;
   g_ctx.nLiq       = 0;
   g_ctx.nZones     = 0;
   g_ctx.nCandles   = 0;
   g_ctx.lastSwHTime = 0;
   g_ctx.lastSwLTime = 0;

   // ─── Run all engines ─────────────────────────────────────────

   // 1. Market structure + phase
   StructureEngine_Compute(g_ctx, high, low, close, time, atr, rates_total);
   if(InpShowInternal)
      StructureEngine_ComputeInternal(g_ctx, high, low, time, rates_total);
   StructureEngine_DetectPhase(g_ctx, atr, rates_total);

   // 2. Liquidity pools
   LiquidityEngine_Compute(g_ctx, high, low, close, time, atr, rates_total);

   // 3. Candle psychology
   CandleEngine_Compute(g_ctx, open, high, low, close, time, atr, rates_total);

   // 4. Smart zones (OB / FVG / Breaker)
   ZoneEngine_Compute(g_ctx, open, high, low, close, time, atr, rates_total);

   // 5. Multi-TF bias
   if(InpUseMTF) MTFEngine_Compute(g_ctx);

   // 6. Premium / Discount grid (must run before scoring)
   PremDiscEngine_Compute(g_ctx, close[0]);

   // 7. Draw on Liquidity (needs liq[] from step 2)
   DOLEngine_Compute(g_ctx, close[0]);

   // 8. Daily / Weekly bias (independent CopyRates call)
   DailyBiasEngine_Compute(g_ctx, close[0]);

   // 9. Setup patterns (needs structure, PD, OB/FVG flags from above)
   SetupEngine_Compute(g_ctx, open, high, low, close, time, rates_total);

   // 10. Trade management SL/TP/RR (needs structure + DOL + PD levels)
   TradeManagerEngine_Compute(g_ctx, close[0]);

   // 11. Educational scoring + narrative
   ScoringEngine_Compute(g_ctx, close[0]);
   ScoringEngine_BuildNarrative(g_ctx, close[0]);

   // ─── Store price data for replay engine ──────────────────────
   g_storedBars = MathMin(PAM_MAX_CANDLES, rates_total);
   ArrayResize(g_open,  g_storedBars);
   ArrayResize(g_high,  g_storedBars);
   ArrayResize(g_low,   g_storedBars);
   ArrayResize(g_close, g_storedBars);
   ArrayResize(g_time,  g_storedBars);
   ArrayResize(g_atr,   g_storedBars);
   for(int i = 0; i < g_storedBars; i++)
   {
      g_open[i]  = open[i];
      g_high[i]  = high[i];
      g_low[i]   = low[i];
      g_close[i] = close[i];
      g_time[i]  = time[i];
      g_atr[i]   = atr[i];
   }

   // ─── Redraw everything ────────────────────────────────────────
   UIEngine_DeleteObjects(g_pfx);

   // Session shading drawn first (furthest back)
   SessionEngine_Draw(g_ctx, time, high, low, rates_total, g_pfx);

   // Kill zone boxes (on top of sessions, same depth)
   KillZoneEngine_Draw(g_ctx, time, high, low, rates_total, g_pfx);

   // Premium/Discount grid
   PremDiscEngine_Draw(g_ctx, time, rates_total, g_pfx, InpShowFibs);

   // Draw on Liquidity targets
   DOLEngine_Draw(g_ctx, time, rates_total, g_pfx);

   // Daily / Weekly reference levels
   DailyBiasEngine_Draw(g_ctx, time, rates_total, g_pfx);

   // Setup pattern markers (drawn last — on top of all zones)
   SetupEngine_Draw(g_ctx, time, open, high, low, close, rates_total, g_pfx);

   // Trade management SL / TP lines
   TradeManagerEngine_Draw(g_ctx, time, rates_total, g_pfx);

   // Structure layers
   StructureEngine_Draw(g_ctx, time, g_pfx, InpBullCol, InpBearCol, InpNeutCol);
   if(InpShowInternal)
      StructureEngine_DrawInternal(g_ctx, g_pfx, InpBullCol, InpBearCol);

   LiquidityEngine_Draw(g_ctx, time, rates_total, g_pfx);
   ZoneEngine_Draw(g_ctx, time, rates_total, g_pfx);
   CandleEngine_Draw(g_ctx, high, low, g_pfx);

   if(InpShowDash)
      UIEngine_UpdateDash(g_ctx, close[0], g_pfx);

   ChartRedraw(0);
   return rates_total;
}

//+------------------------------------------------------------------+
void OnChartEvent(const int     id,
                  const long    &lparam,
                  const double  &dparam,
                  const string  &sparam)
{
   // Click-to-analyze (Replay Mode)
   if(id == CHARTEVENT_CLICK && InpShowReplay && g_storedBars > 0)
   {
      datetime clickTime;
      double   clickPrice;
      int      subwindow;

      if(!ChartXYToTimePrice(0, (int)lparam, (int)dparam,
                              subwindow, clickTime, clickPrice))
         return;
      if(subwindow != 0) return;   // ignore sub-window clicks

      // Find the bar closest to click time
      int clickBar = -1;
      for(int i = 0; i < g_storedBars; i++)
      {
         if(g_time[i] <= clickTime) { clickBar = i; break; }
      }

      ReplayEngine_ShowAnalysis(g_ctx, clickBar, clickTime,
                                g_open, g_high, g_low, g_close, g_atr, g_pfx);

      // Draw R:R box from clicked bar's close as the entry reference
      if(clickBar >= 0 && clickBar < g_storedBars)
         TradeManagerEngine_DrawRRBox(g_ctx, g_close[clickBar], g_time[clickBar],
                                      g_time, g_storedBars, g_pfx);
      ChartRedraw(0);
   }
}
//+------------------------------------------------------------------+
