//+------------------------------------------------------------------+
//|                                              SmartEdgeScorer.mq5 |
//|                          Trade Decision Support Indicator v1.0   |
//|   Scores BUY/SELL setups across 6 components + penalty system    |
//+------------------------------------------------------------------+
#property copyright   "TradeMind"
#property link        "https://trademind.app"
#property version     "1.00"
#property description "Multi-component scoring engine for trade decision support"
#property indicator_chart_window
#property indicator_plots 0

//+------------------------------------------------------------------+
//| SECTION 1 — PROPERTIES, DEFINES, INCLUDES                       |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

#define SES_PREFIX        "SES_"
#define SES_VERSION       "SmartEdge Scorer v1.0"
#define SES_PANEL_X       15
#define SES_PANEL_Y       25
#define SES_PANEL_W       270
#define SES_ROW_H         18
#define SES_FONT          "Consolas"
#define SES_FONT_SZ       8
#define SES_HEADER_SZ     9
#define SES_PIVOT_LOOKBACK 3    // Bars each side to confirm pivot

//+------------------------------------------------------------------+
//| SECTION 2 — INPUT PARAMETERS                                     |
//+------------------------------------------------------------------+

// ── Timeframe ──
input group             "── Timeframe ──"
input ENUM_TIMEFRAMES   InpHTF            = PERIOD_H4;   // Higher Timeframe for trend
input int               InpSwingLookback  = 40;          // Bars to scan for swing points

// ── Indicators ──
input group             "── Indicators ──"
input int               InpEMAPeriod      = 200;         // EMA period
input int               InpRSIPeriod      = 14;          // RSI period
input int               InpADXPeriod      = 14;          // ADX period
input int               InpATRPeriod      = 14;          // ATR period
input int               InpMACDFast       = 12;          // MACD fast EMA
input int               InpMACDSlow       = 26;          // MACD slow EMA
input int               InpMACDSignal     = 9;           // MACD signal

// ── Scoring Weights ──
input group             "── Scoring Weights ──"
input int               InpWtTrend        = 20;          // HTF trend alignment
input int               InpWtStructure    = 15;          // Swing structure quality
input int               InpWtLocation     = 20;          // Proximity to key level
input int               InpWtCandle       = 15;          // Candle confirmation
input int               InpWtMomentum     = 15;          // RSI + MACD momentum
input int               InpWtRR           = 15;          // Risk/Reward room

// ── Penalty Thresholds ──
input group             "── Penalty Thresholds ──"
input double            InpChopADX        = 20.0;        // ADX below = chop penalty -12
input double            InpExtremADX      = 15.0;        // ADX below = extreme chop -20
input double            InpOverextMult    = 2.5;         // ATR multiples = overextension
input double            InpResistProxMult = 0.5;         // ATR multiples = opposition too close

// ── R:R ──
input group             "── R:R ──"
input double            InpRRWeak         = 1.5;         // Minimum acceptable R:R
input double            InpRRGood         = 2.0;         // Good R:R threshold
input double            InpRRExcl         = 3.0;         // Excellent R:R threshold

// ── UI ──
input group             "── UI ──"
input color             InpColorBG        = C'15,18,28'; // Panel background
input color             InpColorHeader    = C'30,35,55'; // Header background
input color             InpColorText      = clrSilver;   // Default text color
input color             InpColorGood      = clrLimeGreen;// Good score color
input color             InpColorMedium    = clrGold;     // Medium score color
input color             InpColorBad       = C'220,80,60';// Bad score color
input bool              InpAutoDetect     = false;       // Auto-detect active position

//+------------------------------------------------------------------+
//| SECTION 3 — DATA STRUCTURES                                      |
//+------------------------------------------------------------------+

// Component score breakdown for one direction
struct SComponentScores
{
   double trend;       // Score from trend component
   double structure;   // Score from structure component
   double location;    // Score from location component
   double candle;      // Score from candle component
   double momentum;    // Score from momentum component
   double rr;          // Score from R:R component
};

// Full scoring result for current bar
struct SScoreResult
{
   double          buyTotal;        // Clamped total 0-100
   double          sellTotal;       // Clamped total 0-100
   SComponentScores buyComp;        // Buy component breakdown
   SComponentScores sellComp;       // Sell component breakdown
   double          buyPenalty;      // Sum of applied buy penalties (<= 0)
   double          sellPenalty;     // Sum of applied sell penalties (<= 0)
   string          buyClass;        // "A+", "Good", "Weak", "Avoid"
   string          sellClass;       // "A+", "Good", "Weak", "Avoid"
   string          reasons;         // Human-readable penalty/signal reasons
   double          suggestStop;     // ATR-based stop distance (price units)
   double          suggestTarget;   // ATR-based target distance (price units)
};

// Post-entry trade health monitoring state
struct STradeHealth
{
   bool   active;        // Is monitoring active?
   string direction;     // "BUY" or "SELL"
   double entryPrice;    // Price when trade was flagged active
   int    barsHeld;      // How many bars since activation
   double exhaustion;    // 0-100 exhaustion score
   string state;         // "Healthy Trend", "Mild Caution", etc.
};

//+------------------------------------------------------------------+
//| SECTION 4 — GLOBAL STATE / HANDLES                               |
//+------------------------------------------------------------------+

// Indicator handles — current timeframe
int g_hEMA_CTF  = INVALID_HANDLE;
int g_hEMA_HTF  = INVALID_HANDLE;
int g_hRSI      = INVALID_HANDLE;
int g_hADX      = INVALID_HANDLE;
int g_hATR      = INVALID_HANDLE;
int g_hMACD     = INVALID_HANDLE;

// Last completed scoring result
SScoreResult   g_score;

// Post-entry monitoring state
STradeHealth   g_health;

// Cached ATR for use across scoring functions
double g_atr = 0.0;

// Track last bar time to detect new bar in OnCalculate
datetime g_lastBarTime = 0;

// UI layout helpers — tracks current Y position during panel build
int g_panelHeight = 0;

//+------------------------------------------------------------------+
//| SECTION 5 — STANDARD EVENT HANDLERS                             |
//+------------------------------------------------------------------+

int OnInit()
{
   // Create indicator handles — current timeframe
   g_hEMA_CTF = iMA(_Symbol, _Period,     InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_hEMA_HTF = iMA(_Symbol, InpHTF,      InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_hRSI     = iRSI(_Symbol, _Period,    InpRSIPeriod, PRICE_CLOSE);
   g_hADX     = iADX(_Symbol, _Period,    InpADXPeriod);
   g_hATR     = iATR(_Symbol, _Period,    InpATRPeriod);
   g_hMACD    = iMACD(_Symbol, _Period,   InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE);

   if(g_hEMA_CTF == INVALID_HANDLE || g_hEMA_HTF == INVALID_HANDLE ||
      g_hRSI == INVALID_HANDLE     || g_hADX == INVALID_HANDLE    ||
      g_hATR == INVALID_HANDLE     || g_hMACD == INVALID_HANDLE)
   {
      Print("SmartEdgeScorer ERROR: Failed to create one or more indicator handles.");
      return INIT_FAILED;
   }

   // Initialise health state
   g_health.active    = false;
   g_health.direction = "";
   g_health.barsHeld  = 0;
   g_health.exhaustion= 0.0;
   g_health.state     = "Inactive";

   // Initialise score result
   ZeroScoreResult(g_score);

   // Build the panel
   BuildPanel();

   // Timer fires every 2 seconds to refresh display only
   EventSetTimer(2);

   ChartRedraw();
   return INIT_SUCCEEDED;
}

//---
void OnDeinit(const int reason)
{
   EventKillTimer();
   DeleteAllUIObjects();
   ChartRedraw();
}

//---
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double   &open[],
                const double   &high[],
                const double   &low[],
                const double   &close[],
                const long     &tick_volume[],
                const long     &volume[],
                const int      &spread[])
{
   // Only rescore on a new completed bar
   if(rates_total < InpSwingLookback + 10) return rates_total;

   bool isNewBar = (rates_total != prev_calculated);
   if(!isNewBar) return rates_total;

   // Run scoring engine
   RunFullScoring();

   // If post-entry monitoring is active, increment bar counter & recompute exhaustion
   if(g_health.active)
   {
      g_health.barsHeld++;
      UpdateTradeHealth();
   }

   // Auto-detect open position if enabled
   if(InpAutoDetect)
      AutoDetectPosition();

   RefreshPanel();
   ChartRedraw();
   return rates_total;
}

//---
void OnTimer()
{
   // Lightweight panel refresh only — no heavy computation
   RefreshPanel();
   ChartRedraw();
}

//---
void OnChartEvent(const int id,
                  const long   &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK) return;

   if(sparam == SES_PREFIX + "BtnEvalBuy")
   {
      RunFullScoring();
      RefreshPanel();
      ChartRedraw();
   }
   else if(sparam == SES_PREFIX + "BtnEvalSell")
   {
      RunFullScoring();
      RefreshPanel();
      ChartRedraw();
   }
   else if(sparam == SES_PREFIX + "BtnActiveBuy")
   {
      ActivateTrade("BUY");
      RefreshPanel();
      ChartRedraw();
   }
   else if(sparam == SES_PREFIX + "BtnActiveSell")
   {
      ActivateTrade("SELL");
      RefreshPanel();
      ChartRedraw();
   }
   else if(sparam == SES_PREFIX + "BtnClearTrade")
   {
      ClearTrade();
      RefreshPanel();
      ChartRedraw();
   }

   // Reset button visual state so it doesn't stay pressed
   if(StringFind(sparam, SES_PREFIX + "Btn") == 0)
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
}

//+------------------------------------------------------------------+
//| SECTION 6 — SCORING ENGINE                                       |
//+------------------------------------------------------------------+

//--- Main entry point: computes all components and assembles g_score
void RunFullScoring()
{
   ZeroScoreResult(g_score);

   // ── Price arrays (start=1 → skip live bar, series order: [0]=most recent closed) ──
   double close[], high[], low[], open[];
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(high,  true);
   ArraySetAsSeries(low,   true);
   ArraySetAsSeries(open,  true);

   int needed = InpSwingLookback + 10;
   if(CopyClose(_Symbol, _Period, 1, needed, close) <= 0) return;
   if(CopyHigh (_Symbol, _Period, 1, needed, high)  <= 0) return;
   if(CopyLow  (_Symbol, _Period, 1, needed, low)   <= 0) return;
   if(CopyOpen (_Symbol, _Period, 1, needed, open)   <= 0) return;

   // ── Indicator buffers ──
   double emaCTF[], emaHTF[], rsi[], adx[], atr[], macdHist[], macdMain[], macdSig[];
   ArraySetAsSeries(emaCTF,   true);
   ArraySetAsSeries(emaHTF,   true);
   ArraySetAsSeries(rsi,      true);
   ArraySetAsSeries(adx,      true);
   ArraySetAsSeries(atr,      true);
   ArraySetAsSeries(macdHist, true);
   ArraySetAsSeries(macdMain, true);
   ArraySetAsSeries(macdSig,  true);

   // Buffer index reference: EMA=0, RSI=0, ADX main=0, ATR=0, MACD main=0 hist=2 sig=1
   if(!SafeCopyBuffer(g_hEMA_CTF, 0, 1, 5,      emaCTF))   return;
   if(!SafeCopyBuffer(g_hEMA_HTF, 0, 1, 5,      emaHTF))   return;
   if(!SafeCopyBuffer(g_hRSI,     0, 1, 10,     rsi))      return;
   if(!SafeCopyBuffer(g_hADX,     0, 1, 5,      adx))      return;
   if(!SafeCopyBuffer(g_hATR,     0, 1, 5,      atr))      return;
   if(!SafeCopyBuffer(g_hMACD,    2, 1, 5,      macdHist)) return;
   if(!SafeCopyBuffer(g_hMACD,    0, 1, 5,      macdMain)) return;
   if(!SafeCopyBuffer(g_hMACD,    1, 1, 5,      macdSig))  return;

   // Cache ATR globally
   g_atr = (ArraySize(atr) > 0 && atr[0] > 0.0) ? atr[0] : _Point * 100;

   double price = close[0];

   // ── Swing point discovery (shared across components) ──
   double pivHigh1=0, pivHigh2=0, pivLow1=0, pivLow2=0;
   FindSwingPoints(high, low, InpSwingLookback, pivHigh1, pivHigh2, pivLow1, pivLow2);

   // ── Component scoring ──
   g_score.buyComp.trend     = ScoreTrend_Buy    (price, emaCTF, emaHTF);
   g_score.sellComp.trend    = ScoreTrend_Sell   (price, emaCTF, emaHTF);

   g_score.buyComp.structure  = ScoreStructure_Buy (pivHigh1, pivHigh2, pivLow1, pivLow2);
   g_score.sellComp.structure = ScoreStructure_Sell(pivHigh1, pivHigh2, pivLow1, pivLow2);

   g_score.buyComp.location   = ScoreLocation_Buy (price, pivLow1);
   g_score.sellComp.location  = ScoreLocation_Sell(price, pivHigh1);

   g_score.buyComp.candle     = ScoreCandle_Buy (close, open, high, low);
   g_score.sellComp.candle    = ScoreCandle_Sell(close, open, high, low);

   g_score.buyComp.momentum   = ScoreMomentum_Buy (rsi, macdHist);
   g_score.sellComp.momentum  = ScoreMomentum_Sell(rsi, macdHist);

   double buyStop=0, buyTarget=0, sellStop=0, sellTarget=0;
   g_score.buyComp.rr  = ScoreRR_Buy (price, pivHigh1, pivLow1,  buyStop,  buyTarget);
   g_score.sellComp.rr = ScoreRR_Sell(price, pivHigh1, pivLow1, sellStop, sellTarget);

   // ── Penalty calculation ──
   string penaltyLog = "";
   g_score.buyPenalty  = ComputePenalties(price, emaCTF[0], adx[0], g_atr, true,  penaltyLog);
   string penaltyLogSell = "";
   g_score.sellPenalty = ComputePenalties(price, emaCTF[0], adx[0], g_atr, false, penaltyLogSell);

   // Resistance proximity penalty: nearest opposition level too close kills R:R
   double proxBuy  = PenaltyResistanceProximity(price, pivHigh1, g_atr, true);
   double proxSell = PenaltyResistanceProximity(price, pivLow1,  g_atr, false);
   if(proxBuy  < 0.0) { g_score.buyPenalty  += proxBuy;  penaltyLog     += "ResistClose(-12) "; }
   if(proxSell < 0.0) { g_score.sellPenalty += proxSell; penaltyLogSell += "SupportClose(-12) "; }

   // Merge penalty logs
   if(StringLen(penaltyLog) == 0) penaltyLog = "No buy penalties";
   if(StringLen(penaltyLogSell) > 0)
      penaltyLog += " | " + penaltyLogSell;
   else
      penaltyLog += " | No sell penalties";
   g_score.reasons = penaltyLog;

   // ── Raw component sums ──
   double rawBuy  = g_score.buyComp.trend  + g_score.buyComp.structure  +
                    g_score.buyComp.location + g_score.buyComp.candle    +
                    g_score.buyComp.momentum + g_score.buyComp.rr;
   double rawSell = g_score.sellComp.trend + g_score.sellComp.structure +
                    g_score.sellComp.location + g_score.sellComp.candle  +
                    g_score.sellComp.momentum + g_score.sellComp.rr;

   // ── Final totals (clamped 0-100) ──
   g_score.buyTotal  = MathMax(0.0, MathMin(100.0, rawBuy  + g_score.buyPenalty));
   g_score.sellTotal = MathMax(0.0, MathMin(100.0, rawSell + g_score.sellPenalty));

   // ── Classification ──
   g_score.buyClass  = ClassifyScore(g_score.buyTotal);
   g_score.sellClass = ClassifyScore(g_score.sellTotal);

   // ── ATR-based suggestion distances ──
   g_score.suggestStop   = g_atr * 1.5;
   g_score.suggestTarget = g_atr * 3.0;
}

//--- Classify a total score into a grade string
string ClassifyScore(double total)
{
   if(total >= 80.0) return "A+";
   if(total >= 60.0) return "Good";
   if(total >= 40.0) return "Weak";
   return "Avoid";
}

//--- Clamp helper
double Clamp(double val, double mn, double mx)
{
   return MathMax(mn, MathMin(mx, val));
}

//--- Find the two most recent pivot highs and pivot lows
void FindSwingPoints(const double &high[],
                     const double &low[],
                     int          lookback,
                     double       &ph1,
                     double       &ph2,
                     double       &pl1,
                     double       &pl2)
{
   ph1 = 0; ph2 = 0; pl1 = 0; pl2 = 0;
   int phCount = 0, plCount = 0;
   int sz = ArraySize(high);
   int limit = MathMin(lookback, sz - 2);

   for(int i = 1; i < limit && (phCount < 2 || plCount < 2); i++)
   {
      // Pivot high: higher than both neighbours
      if(phCount < 2 && high[i] > high[i-1] && high[i] > high[i+1])
      {
         if(phCount == 0) ph1 = high[i];
         else             ph2 = high[i];
         phCount++;
      }
      // Pivot low: lower than both neighbours
      if(plCount < 2 && low[i] < low[i-1] && low[i] < low[i+1])
      {
         if(plCount == 0) pl1 = low[i];
         else             pl2 = low[i];
         plCount++;
      }
   }
}

//--- TREND SCORE — BUY
double ScoreTrend_Buy(double price, const double &emaCTF[], const double &emaHTF[])
{
   if(ArraySize(emaCTF) < 2 || ArraySize(emaHTF) < 2) return 0.0;

   double htfWeight = InpWtTrend * 0.60;
   double ctfWeight = InpWtTrend * 0.40;
   double htfScore  = 0.0;
   double ctfScore  = 0.0;

   // HTF: price above EMA and EMA slope rising = full; price above only = 40%; counter = 0
   bool htfAbove   = (price > emaHTF[0]);
   bool htfRising  = (emaHTF[0] > emaHTF[1]);
   if(htfAbove && htfRising)      htfScore = htfWeight;
   else if(htfAbove)              htfScore = htfWeight * 0.40;
   else                           htfScore = 0.0;

   // CTF: price above EMA = full, else 0
   if(price > emaCTF[0])          ctfScore = ctfWeight;
   else                           ctfScore = 0.0;

   return htfScore + ctfScore;
}

//--- TREND SCORE — SELL
double ScoreTrend_Sell(double price, const double &emaCTF[], const double &emaHTF[])
{
   if(ArraySize(emaCTF) < 2 || ArraySize(emaHTF) < 2) return 0.0;

   double htfWeight = InpWtTrend * 0.60;
   double ctfWeight = InpWtTrend * 0.40;
   double htfScore  = 0.0;
   double ctfScore  = 0.0;

   // HTF: price below EMA and EMA slope falling = full; below only = 40%; counter = 0
   bool htfBelow   = (price < emaHTF[0]);
   bool htfFalling = (emaHTF[0] < emaHTF[1]);
   if(htfBelow && htfFalling)     htfScore = htfWeight;
   else if(htfBelow)              htfScore = htfWeight * 0.40;
   else                           htfScore = 0.0;

   // CTF: price below EMA = full, else 0
   if(price < emaCTF[0])          ctfScore = ctfWeight;
   else                           ctfScore = 0.0;

   return htfScore + ctfScore;
}

//--- STRUCTURE SCORE — BUY
double ScoreStructure_Buy(double ph1, double ph2, double pl1, double pl2)
{
   // Need at least one pivot of each type to assess structure
   if(ph1 == 0 || pl1 == 0) return 0.0;

   bool hasHH = (ph2 > 0 && ph1 > ph2);  // Most recent pivot high > prior = Higher High
   bool hasHL = (pl2 > 0 && pl1 > pl2);  // Most recent pivot low  > prior = Higher Low
   bool hasLL = (pl2 > 0 && pl1 < pl2);  // Most recent pivot low  < prior = Lower Low
   bool hasLH = (ph2 > 0 && ph1 < ph2);  // Most recent pivot high < prior = Lower High

   if(hasHH && hasHL) return (double)InpWtStructure;           // Full — clean uptrend
   if(hasHL)          return InpWtStructure * 0.60;            // HL only
   if(hasHH)          return InpWtStructure * 0.40;            // HH only
   if(hasLL && hasLH) return 0.0;                              // Downtrend — no buy credit
   return InpWtStructure * 0.20;                               // Unclear structure — minimal
}

//--- STRUCTURE SCORE — SELL
double ScoreStructure_Sell(double ph1, double ph2, double pl1, double pl2)
{
   if(ph1 == 0 || pl1 == 0) return 0.0;

   bool hasLL = (pl2 > 0 && pl1 < pl2);
   bool hasLH = (ph2 > 0 && ph1 < ph2);
   bool hasHH = (ph2 > 0 && ph1 > ph2);
   bool hasHL = (pl2 > 0 && pl1 > pl2);

   if(hasLL && hasLH) return (double)InpWtStructure;           // Full — clean downtrend
   if(hasLH)          return InpWtStructure * 0.60;            // LH only
   if(hasLL)          return InpWtStructure * 0.40;            // LL only
   if(hasHH && hasHL) return 0.0;                              // Uptrend — no sell credit
   return InpWtStructure * 0.20;
}

//--- LOCATION SCORE — BUY (proximity to nearest swing low)
double ScoreLocation_Buy(double price, double nearestSwingLow)
{
   if(nearestSwingLow <= 0.0 || g_atr <= 0.0) return 0.0;
   double dist = price - nearestSwingLow;
   if(dist < 0.0) dist = -dist; // Absolute distance

   if(dist <= 0.5 * g_atr) return (double)InpWtLocation;
   if(dist <= 1.5 * g_atr) return InpWtLocation * 0.70;
   if(dist <= 3.0 * g_atr) return InpWtLocation * 0.30;
   return 0.0;
}

//--- LOCATION SCORE — SELL (proximity to nearest swing high)
double ScoreLocation_Sell(double price, double nearestSwingHigh)
{
   if(nearestSwingHigh <= 0.0 || g_atr <= 0.0) return 0.0;
   double dist = nearestSwingHigh - price;
   if(dist < 0.0) dist = -dist;

   if(dist <= 0.5 * g_atr) return (double)InpWtLocation;
   if(dist <= 1.5 * g_atr) return InpWtLocation * 0.70;
   if(dist <= 3.0 * g_atr) return InpWtLocation * 0.30;
   return 0.0;
}

//--- CANDLE SCORE — BUY
double ScoreCandle_Buy(const double &close[], const double &open[],
                       const double &high[],  const double &low[])
{
   if(ArraySize(close) < 2) return 0.0;

   // Bar [0] = last closed candle (arrays start at 1 in CopyXxx, so index 0 = bar-1)
   double c0 = close[0], o0 = open[0], h0 = high[0], l0 = low[0];
   double range0 = h0 - l0;
   if(range0 <= 0.0) return 0.0;

   double body0      = MathAbs(c0 - o0);
   double bodyRatio0 = body0 / range0;
   double lowerWick  = MathMin(c0, o0) - l0;

   bool isBull = (c0 > o0);

   // Strong bullish candle
   if(isBull && bodyRatio0 >= 0.60)
      return (double)InpWtCandle;

   // Bullish engulfing: close0 > open1 AND open0 < close1 AND bar1 was bearish
   if(ArraySize(close) >= 2)
   {
      double c1 = close[1], o1 = open[1];
      bool bar1Bearish = (c1 < o1);
      if(isBull && bar1Bearish && c0 > o1 && o0 < c1)
         return InpWtCandle * 0.90;
   }

   // Pin bar (hammer): lower wick >= 2 * body and lower wick >= 55% of range
   if(body0 > 0.0 && lowerWick >= 2.0 * body0 && lowerWick >= 0.55 * range0)
      return InpWtCandle * 0.80;

   // Weak bullish
   if(isBull && bodyRatio0 >= 0.30)
      return InpWtCandle * 0.40;

   // Doji
   if(bodyRatio0 < 0.20)
      return InpWtCandle * 0.15;

   // Bearish candle
   return 0.0;
}

//--- CANDLE SCORE — SELL
double ScoreCandle_Sell(const double &close[], const double &open[],
                        const double &high[],  const double &low[])
{
   if(ArraySize(close) < 2) return 0.0;

   double c0 = close[0], o0 = open[0], h0 = high[0], l0 = low[0];
   double range0 = h0 - l0;
   if(range0 <= 0.0) return 0.0;

   double body0      = MathAbs(c0 - o0);
   double bodyRatio0 = body0 / range0;
   double upperWick  = h0 - MathMax(c0, o0);

   bool isBear = (c0 < o0);

   // Strong bearish candle
   if(isBear && bodyRatio0 >= 0.60)
      return (double)InpWtCandle;

   // Bearish engulfing
   if(ArraySize(close) >= 2)
   {
      double c1 = close[1], o1 = open[1];
      bool bar1Bull = (c1 > o1);
      if(isBear && bar1Bull && c0 < o1 && o0 > c1)
         return InpWtCandle * 0.90;
   }

   // Shooting star: upper wick >= 2 * body and upper wick >= 55% of range
   if(body0 > 0.0 && upperWick >= 2.0 * body0 && upperWick >= 0.55 * range0)
      return InpWtCandle * 0.80;

   // Weak bearish
   if(isBear && bodyRatio0 >= 0.30)
      return InpWtCandle * 0.40;

   // Doji
   if(bodyRatio0 < 0.20)
      return InpWtCandle * 0.15;

   return 0.0;
}

//--- MOMENTUM SCORE — BUY
double ScoreMomentum_Buy(const double &rsi[], const double &macdHist[])
{
   if(ArraySize(rsi) < 2 || ArraySize(macdHist) < 2) return 0.0;

   double rsiWeight  = InpWtMomentum * 0.60;
   double macdWeight = InpWtMomentum * 0.40;
   double rsiScore   = 0.0;
   double macdScore  = 0.0;

   double r0 = rsi[0], r1 = rsi[1];
   bool rsiRising = (r0 > r1);

   if(r0 > 50.0 && rsiRising)          rsiScore = rsiWeight;
   else if(r0 > 50.0)                  rsiScore = rsiWeight * (35.0 / 60.0);
   else if(r0 > 40.0 && rsiRising)     rsiScore = rsiWeight * (20.0 / 60.0);
   else                                rsiScore = 0.0;

   double h0 = macdHist[0], h1 = macdHist[1];
   bool histExpanding = (h0 > h1 && h0 > 0.0);
   bool histImproving = (h0 > h1 && h0 < 0.0);

   if(h0 > 0.0 && histExpanding)       macdScore = macdWeight;
   else if(h0 > 0.0)                   macdScore = macdWeight * (25.0 / 40.0);
   else if(histImproving)              macdScore = macdWeight * (10.0 / 40.0);
   else                                macdScore = 0.0;

   return rsiScore + macdScore;
}

//--- MOMENTUM SCORE — SELL
double ScoreMomentum_Sell(const double &rsi[], const double &macdHist[])
{
   if(ArraySize(rsi) < 2 || ArraySize(macdHist) < 2) return 0.0;

   double rsiWeight  = InpWtMomentum * 0.60;
   double macdWeight = InpWtMomentum * 0.40;
   double rsiScore   = 0.0;
   double macdScore  = 0.0;

   double r0 = rsi[0], r1 = rsi[1];
   bool rsiFalling = (r0 < r1);

   if(r0 < 50.0 && rsiFalling)         rsiScore = rsiWeight;
   else if(r0 < 50.0)                  rsiScore = rsiWeight * (35.0 / 60.0);
   else if(r0 < 60.0 && rsiFalling)    rsiScore = rsiWeight * (20.0 / 60.0);
   else                                rsiScore = 0.0;

   double h0 = macdHist[0], h1 = macdHist[1];
   bool histContracting = (h0 < h1 && h0 < 0.0);
   bool histShrinking   = (h0 < h1 && h0 > 0.0);

   if(h0 < 0.0 && histContracting)     macdScore = macdWeight;
   else if(h0 < 0.0)                   macdScore = macdWeight * (25.0 / 40.0);
   else if(histShrinking)              macdScore = macdWeight * (10.0 / 40.0);
   else                                macdScore = 0.0;

   return rsiScore + macdScore;
}

//--- R:R SCORE — BUY
double ScoreRR_Buy(double price, double nearestHigh, double nearestLow,
                   double &stopOut, double &targetOut)
{
   if(g_atr <= 0.0) return 0.0;

   // Stop = nearest swing low below price
   double stopLevel = nearestLow;
   if(stopLevel <= 0.0 || price <= stopLevel)
      stopLevel = price - g_atr * 1.5;

   double stopDist = price - stopLevel;
   if(stopDist < 0.3 * g_atr) stopDist = g_atr * 1.5;

   // Target = nearest swing high above price
   double targetLevel = nearestHigh;
   if(targetLevel <= 0.0 || targetLevel <= price)
      targetLevel = price + g_atr * 3.0;

   double targetDist = targetLevel - price;
   if(targetDist < 0.3 * g_atr) targetDist = g_atr * 3.0;

   stopOut   = stopDist;
   targetOut = targetDist;

   double rr = targetDist / stopDist;
   if(rr >= InpRRExcl)  return (double)InpWtRR;
   if(rr >= InpRRGood)  return InpWtRR * 0.75;
   if(rr >= InpRRWeak)  return InpWtRR * 0.40;
   return 0.0;
}

//--- R:R SCORE — SELL
double ScoreRR_Sell(double price, double nearestHigh, double nearestLow,
                    double &stopOut, double &targetOut)
{
   if(g_atr <= 0.0) return 0.0;

   // Stop = nearest swing high above price
   double stopLevel = nearestHigh;
   if(stopLevel <= 0.0 || price >= stopLevel)
      stopLevel = price + g_atr * 1.5;

   double stopDist = stopLevel - price;
   if(stopDist < 0.3 * g_atr) stopDist = g_atr * 1.5;

   // Target = nearest swing low below price
   double targetLevel = nearestLow;
   if(targetLevel <= 0.0 || targetLevel >= price)
      targetLevel = price - g_atr * 3.0;

   double targetDist = price - targetLevel;
   if(targetDist < 0.3 * g_atr) targetDist = g_atr * 3.0;

   stopOut   = stopDist;
   targetOut = targetDist;

   double rr = targetDist / stopDist;
   if(rr >= InpRRExcl)  return (double)InpWtRR;
   if(rr >= InpRRGood)  return InpWtRR * 0.75;
   if(rr >= InpRRWeak)  return InpWtRR * 0.40;
   return 0.0;
}

//--- PENALTY COMPUTATION
//    Returns total penalty (negative value or zero)
double ComputePenalties(double price, double ema200, double adxVal, double atr,
                        bool isBuy, string &logOut)
{
   double penalty = 0.0;
   logOut = "";

   // ADX extreme chop
   if(adxVal < InpExtremADX)
   {
      penalty -= 20.0;
      logOut += "ExtremeChop(-20) ";
   }
   // Regular chop (only if not already in extreme category)
   else if(adxVal < InpChopADX)
   {
      penalty -= 12.0;
      logOut += "Chop(-12) ";
   }

   // Overextension check
   if(atr > 0.0)
   {
      if(isBuy && price > ema200 + InpOverextMult * atr)
      {
         penalty -= 10.0;
         logOut += "Overext(-10) ";
      }
      else if(!isBuy && price < ema200 - InpOverextMult * atr)
      {
         penalty -= 10.0;
         logOut += "Overext(-10) ";
      }
   }

   return penalty;
}

//--- Apply resistance proximity penalty (requires swing data — called after scoring)
//    Integrated into RunFullScoring via ComputePenalties; separate helper for clarity
double PenaltyResistanceProximity(double price, double oppositionLevel, double atr, bool isBuy)
{
   if(oppositionLevel <= 0.0 || atr <= 0.0) return 0.0;
   double dist = isBuy ? (oppositionLevel - price) : (price - oppositionLevel);
   if(dist < 0.0) dist = 0.0;
   if(dist < InpResistProxMult * atr) return -12.0;
   return 0.0;
}

//+------------------------------------------------------------------+
//| SECTION 7 — POST-ENTRY MONITOR                                   |
//+------------------------------------------------------------------+

void ActivateTrade(string direction)
{
   double close[];
   ArraySetAsSeries(close, true);
   if(CopyClose(_Symbol, _Period, 1, 1, close) <= 0) return;

   g_health.active     = true;
   g_health.direction  = direction;
   g_health.entryPrice = close[0];
   g_health.barsHeld   = 0;
   g_health.exhaustion = 0.0;
   g_health.state      = "Healthy Trend";
}

void ClearTrade()
{
   g_health.active     = false;
   g_health.direction  = "";
   g_health.entryPrice = 0.0;
   g_health.barsHeld   = 0;
   g_health.exhaustion = 0.0;
   g_health.state      = "Inactive";
}

void AutoDetectPosition()
{
   bool posOpen = false;
   string dir   = "";

   for(int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      posOpen = true;
      dir = (ptype == POSITION_TYPE_BUY) ? "BUY" : "SELL";
      break;
   }

   if(!posOpen && g_health.active)
      ClearTrade();
   else if(posOpen && !g_health.active)
      ActivateTrade(dir);
}

void UpdateTradeHealth()
{
   double close[], high[], low[], open[], rsi[];
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(high,  true);
   ArraySetAsSeries(low,   true);
   ArraySetAsSeries(open,  true);
   ArraySetAsSeries(rsi,   true);

   int needed = 15;
   if(CopyClose(_Symbol, _Period, 1, needed, close) <= 0) return;
   if(CopyHigh (_Symbol, _Period, 1, needed, high)  <= 0) return;
   if(CopyLow  (_Symbol, _Period, 1, needed, low)   <= 0) return;
   if(CopyOpen (_Symbol, _Period, 1, needed, open)   <= 0) return;
   if(!SafeCopyBuffer(g_hRSI, 0, 1, needed, rsi))         return;

   bool isBuy = (g_health.direction == "BUY");
   g_health.exhaustion = ComputeExhaustionScore(isBuy, close, high, low, open, rsi);
   g_health.state      = ExhaustionToState(g_health.exhaustion);
}

//--- Compute exhaustion score 0-100 for post-entry monitoring
double ComputeExhaustionScore(bool isBuy,
                              const double &close[],
                              const double &high[],
                              const double &low[],
                              const double &open[],
                              const double &rsi[])
{
   double score = 0.0;
   int sz = ArraySize(close);
   if(sz < 10) return 0.0;

   // ── 1. Body shrinkage (25 pts) ──
   double sumBody10 = 0.0;
   for(int i = 0; i < 10 && i < sz; i++)
      sumBody10 += MathAbs(close[i] - open[i]);
   double avgBody10 = sumBody10 / 10.0;

   double sumBody3 = 0.0;
   for(int i = 0; i < 3 && i < sz; i++)
      sumBody3 += MathAbs(close[i] - open[i]);
   double avgBody3 = sumBody3 / 3.0;

   if(avgBody10 > 0.0)
   {
      double shrinkRatio = avgBody3 / avgBody10;
      if(shrinkRatio < 0.40)      score += 25.0;
      else if(shrinkRatio < 0.60) score += 15.0;
      else if(shrinkRatio < 0.80) score += 5.0;
   }

   // ── 2. Rejection wick expansion (20 pts) ──
   double range0 = high[0] - low[0];
   if(range0 > 0.0)
   {
      if(isBuy)
      {
         double upperWick = high[0] - MathMax(close[0], open[0]);
         double uwRatio   = upperWick / range0;
         if(uwRatio > 0.55)      score += 20.0;
         else if(uwRatio > 0.35) score += 10.0;
      }
      else
      {
         double lowerWick = MathMin(close[0], open[0]) - low[0];
         double lwRatio   = lowerWick / range0;
         if(lwRatio > 0.55)      score += 20.0;
         else if(lwRatio > 0.35) score += 10.0;
      }
   }

   // ── 3. RSI divergence (30 pts) ──
   if(ArraySize(rsi) >= 5)
   {
      double r0 = rsi[0], r4 = rsi[4];
      if(isBuy)
      {
         // Price made new high but RSI lower
         bool newHigh = (high[0] >= high[1] && high[0] >= high[2] &&
                         high[0] >= high[3] && high[0] >= high[4]);
         if(newHigh)
         {
            if(r0 < r4 - 3.0) score += 30.0;
            else if(r0 < r4)  score += 15.0;
         }
      }
      else
      {
         // Price made new low but RSI higher
         bool newLow = (low[0] <= low[1] && low[0] <= low[2] &&
                        low[0] <= low[3] && low[0] <= low[4]);
         if(newLow)
         {
            if(r0 > r4 + 3.0) score += 30.0;
            else if(r0 > r4)  score += 15.0;
         }
      }
   }

   // ── 4. Stall detection (15 pts) ──
   if(isBuy)
   {
      bool newHigh5 = false;
      for(int i = 1; i < 5 && i < sz; i++)
         if(high[0] < high[i]) { newHigh5 = true; break; }
      // If NOT making new highs (stalling)
      if(!newHigh5)
      {
         if(g_health.barsHeld > 3) score += 15.0;
         else if(g_health.barsHeld > 2) score += 8.0;
      }
   }
   else
   {
      bool newLow5 = false;
      for(int i = 1; i < 5 && i < sz; i++)
         if(low[0] > low[i]) { newLow5 = true; break; }
      if(!newLow5)
      {
         if(g_health.barsHeld > 3) score += 15.0;
         else if(g_health.barsHeld > 2) score += 8.0;
      }
   }

   // ── 5. Momentum contraction (10 pts) ──
   double sumRecent3 = 0.0;
   for(int i = 0; i < 3 && i < sz; i++)
      sumRecent3 += MathAbs(close[i] - open[i]);
   double avgRecent3b = sumRecent3 / 3.0;

   double sumAll10 = 0.0;
   for(int i = 0; i < 10 && i < sz; i++)
      sumAll10 += MathAbs(close[i] - open[i]);
   double avgAll10b = sumAll10 / 10.0;

   if(avgAll10b > 0.0 && avgRecent3b < 0.50 * avgAll10b)
      score += 10.0;

   return MathMin(100.0, score);
}

//--- Map exhaustion score to a descriptive state string
string ExhaustionToState(double ex)
{
   if(ex < 15.0) return "Healthy Trend";
   if(ex < 30.0) return "Mild Caution";
   if(ex < 50.0) return "Momentum Weakening";
   if(ex < 65.0) return "Exhaustion Watch";
   if(ex < 80.0) return "Exit Watch";
   return "Reversal Confirmed";
}

//+------------------------------------------------------------------+
//| SECTION 8 — UI (PANEL + BUTTONS)                                 |
//+------------------------------------------------------------------+

//--- Total row count for sizing: header(1) + preentry(4) + breakdown(8) + health(3) + zones(2) + notes(1) + gaps(4)
#define PANEL_ROWS 30

//--- Helper to create a rectangle label (background block)
void CreateRect(string name, int x, int y, int w, int h, color bg, int corner=CORNER_LEFT_UPPER)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,      w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,      h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,    bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      bg);
   ObjectSetInteger(0, name, OBJPROP_CORNER,     corner);
   ObjectSetInteger(0, name, OBJPROP_BACK,       true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//--- Helper to create or update a text label
void CreateLabel(string name, int x, int y, string text, color clr,
                 int fontSize=SES_FONT_SZ, string anchor="LEFT")
{
   ENUM_ANCHOR_POINT ap = ANCHOR_LEFT_UPPER;
   if(anchor == "RIGHT") ap = ANCHOR_RIGHT_UPPER;

   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
   ObjectSetString (0, name, OBJPROP_TEXT,       text);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clr);
   ObjectSetString (0, name, OBJPROP_FONT,       SES_FONT);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   fontSize);
   ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR,     ap);
   ObjectSetInteger(0, name, OBJPROP_BACK,       false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

//--- Update text on an existing label (noop if not found)
void SetLabelText(string name, string text)
{
   if(ObjectFind(0, name) >= 0)
      ObjectSetString(0, name, OBJPROP_TEXT, text);
}

//--- Update color on an existing label
void SetLabelColor(string name, color clr)
{
   if(ObjectFind(0, name) >= 0)
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
}

//--- Create a button
void CreateButton(string name, int x, int y, int w, int h,
                  string text, color bg, color fg)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,      w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,      h);
   ObjectSetString (0, name, OBJPROP_TEXT,       text);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,    bg);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      fg);
   ObjectSetString (0, name, OBJPROP_FONT,       SES_FONT);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   SES_FONT_SZ);
   ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BACK,       false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_STATE,      false);
}

//--- Build the full panel skeleton (called once on init)
void BuildPanel()
{
   int x  = SES_PANEL_X;
   int y  = SES_PANEL_Y;
   int w  = SES_PANEL_W;
   int rh = SES_ROW_H;

   // ── Main background ──
   int totalH = rh * PANEL_ROWS + 10;
   g_panelHeight = totalH;
   CreateRect(SES_PREFIX + "BG", x, y, w, totalH, InpColorBG);

   int curY = y;

   // ── Header ──
   CreateRect(SES_PREFIX + "HeaderBG", x, curY, w, rh + 4, InpColorHeader);
   CreateLabel(SES_PREFIX + "HeaderTxt", x + 8, curY + 3,
               "▪ " + SES_VERSION, InpColorText, SES_HEADER_SZ);
   curY += rh + 6;

   // ── Pre-entry section title ──
   CreateLabel(SES_PREFIX + "TitlePre", x + 6, curY, "─ PRE-ENTRY SCORES ─", InpColorText, 7);
   curY += rh;

   // BUY score row
   CreateLabel(SES_PREFIX + "LblBuy",      x + 6,       curY, "BUY  Score:", InpColorText);
   CreateLabel(SES_PREFIX + "ValBuyScore", x + 110,     curY, "---",         InpColorText);
   CreateLabel(SES_PREFIX + "ValBuyClass", x + 160,     curY, "---",         InpColorText);
   curY += rh;

   // SELL score row
   CreateLabel(SES_PREFIX + "LblSell",      x + 6,      curY, "SELL Score:", InpColorText);
   CreateLabel(SES_PREFIX + "ValSellScore", x + 110,    curY, "---",         InpColorText);
   CreateLabel(SES_PREFIX + "ValSellClass", x + 160,    curY, "---",         InpColorText);
   curY += rh + 4;

   // ── Breakdown section title ──
   CreateLabel(SES_PREFIX + "TitleBrk", x + 6, curY, "─ BREAKDOWN  Buy | Sell ─", InpColorText, 7);
   curY += rh;

   string compNames[6] = {"Trend", "Structure", "Location", "Candle", "Momentum", "R:R"};
   string compKeys[6]  = {"Trend", "Structure", "Location", "Candle", "Momentum", "RR"};
   for(int i = 0; i < 6; i++)
   {
      CreateLabel(SES_PREFIX + "BrkLbl"  + compKeys[i], x + 6,   curY, compNames[i] + ":", InpColorText, 7);
      CreateLabel(SES_PREFIX + "BrkBuy"  + compKeys[i], x + 110, curY, "--",  InpColorText, 7);
      CreateLabel(SES_PREFIX + "BrkSep"  + compKeys[i], x + 140, curY, "|",   InpColorText, 7);
      CreateLabel(SES_PREFIX + "BrkSell" + compKeys[i], x + 155, curY, "--",  InpColorText, 7);
      curY += rh - 1;
   }
   // Penalty row
   CreateLabel(SES_PREFIX + "BrkLblPen",  x + 6,   curY, "Penalty:", InpColorText, 7);
   CreateLabel(SES_PREFIX + "BrkBuyPen",  x + 110, curY, "--",       InpColorText, 7);
   CreateLabel(SES_PREFIX + "BrkSepPen",  x + 140, curY, "|",        InpColorText, 7);
   CreateLabel(SES_PREFIX + "BrkSellPen", x + 155, curY, "--",       InpColorText, 7);
   curY += rh + 4;

   // ── Active trade section ──
   CreateLabel(SES_PREFIX + "TitleTrade", x + 6, curY, "─ ACTIVE TRADE ─", InpColorText, 7);
   curY += rh;

   CreateLabel(SES_PREFIX + "LblTDir",  x + 6,   curY, "Direction:",  InpColorText);
   CreateLabel(SES_PREFIX + "ValTDir",  x + 110,  curY, "None",       InpColorText);
   curY += rh;

   CreateLabel(SES_PREFIX + "LblTExh",  x + 6,   curY, "Exhaustion:", InpColorText);
   CreateLabel(SES_PREFIX + "ValTExh",  x + 110,  curY, "0.0",        InpColorText);
   curY += rh;

   CreateLabel(SES_PREFIX + "LblTSt",  x + 6,    curY, "State:",      InpColorText);
   CreateLabel(SES_PREFIX + "ValTSt",  x + 110,   curY, "Inactive",   InpColorText);
   curY += rh + 4;

   // ── Suggested zones ──
   CreateLabel(SES_PREFIX + "TitleZones", x + 6, curY, "─ SUGGESTED ZONES ─", InpColorText, 7);
   curY += rh;

   CreateLabel(SES_PREFIX + "LblStop",   x + 6,  curY, "StopZone:",    InpColorText);
   CreateLabel(SES_PREFIX + "ValStop",   x + 110, curY, "---",         InpColorText);
   curY += rh;

   CreateLabel(SES_PREFIX + "LblTarget", x + 6,  curY, "TargetZone:", InpColorText);
   CreateLabel(SES_PREFIX + "ValTarget", x + 110, curY, "---",         InpColorText);
   curY += rh + 4;

   // ── Notes / reasons ──
   CreateLabel(SES_PREFIX + "LblNotes", x + 6, curY, "Notes:", InpColorText, 7);
   curY += rh;
   CreateLabel(SES_PREFIX + "ValNotes", x + 6, curY, "", InpColorText, 7);
   curY += rh + 6;

   // ── Buttons (two rows of 2 + 1 clear) ──
   int btnW = (w - 18) / 2;
   int btnH = 16;

   CreateButton(SES_PREFIX + "BtnEvalBuy",    x + 4,          curY, btnW, btnH,
                "Evaluate Buy",  C'20,60,40',  clrLimeGreen);
   CreateButton(SES_PREFIX + "BtnEvalSell",   x + 6 + btnW,   curY, btnW, btnH,
                "Evaluate Sell", C'60,20,20',  InpColorBad);
   curY += btnH + 3;

   CreateButton(SES_PREFIX + "BtnActiveBuy",  x + 4,          curY, btnW, btnH,
                "Set Active BUY",  C'10,50,80',  clrDeepSkyBlue);
   CreateButton(SES_PREFIX + "BtnActiveSell", x + 6 + btnW,   curY, btnW, btnH,
                "Set Active SELL", C'80,30,10',  clrOrange);
   curY += btnH + 3;

   CreateButton(SES_PREFIX + "BtnClearTrade", x + 4,          curY, w - 8, btnH,
                "Clear Trade",     C'35,35,55',  clrSilver);
}

//--- Refresh all dynamic values on the panel
void RefreshPanel()
{
   // ── Pre-entry scores ──
   string buyScoreStr  = DoubleToString(g_score.buyTotal,  1);
   string sellScoreStr = DoubleToString(g_score.sellTotal, 1);

   SetLabelText(SES_PREFIX + "ValBuyScore",  buyScoreStr);
   SetLabelText(SES_PREFIX + "ValSellScore", sellScoreStr);
   SetLabelText(SES_PREFIX + "ValBuyClass",  "[" + g_score.buyClass  + "]");
   SetLabelText(SES_PREFIX + "ValSellClass", "[" + g_score.sellClass + "]");

   SetLabelColor(SES_PREFIX + "ValBuyScore",  ScoreColor(g_score.buyTotal));
   SetLabelColor(SES_PREFIX + "ValBuyClass",  ClassColor(g_score.buyClass));
   SetLabelColor(SES_PREFIX + "ValSellScore", ScoreColor(g_score.sellTotal));
   SetLabelColor(SES_PREFIX + "ValSellClass", ClassColor(g_score.sellClass));

   // ── Breakdown ──
   string keys[6]      = {"Trend","Structure","Location","Candle","Momentum","RR"};
   double buyVals[6]   = {g_score.buyComp.trend, g_score.buyComp.structure,
                          g_score.buyComp.location, g_score.buyComp.candle,
                          g_score.buyComp.momentum, g_score.buyComp.rr};
   double sellVals[6]  = {g_score.sellComp.trend, g_score.sellComp.structure,
                          g_score.sellComp.location, g_score.sellComp.candle,
                          g_score.sellComp.momentum, g_score.sellComp.rr};
   int    maxVals[6]   = {InpWtTrend, InpWtStructure, InpWtLocation,
                          InpWtCandle, InpWtMomentum, InpWtRR};

   for(int i = 0; i < 6; i++)
   {
      string bStr = DoubleToString(buyVals[i],  1);
      string sStr = DoubleToString(sellVals[i], 1);
      SetLabelText (SES_PREFIX + "BrkBuy"  + keys[i], bStr);
      SetLabelText (SES_PREFIX + "BrkSell" + keys[i], sStr);
      SetLabelColor(SES_PREFIX + "BrkBuy"  + keys[i], ComponentColor(buyVals[i],  maxVals[i]));
      SetLabelColor(SES_PREFIX + "BrkSell" + keys[i], ComponentColor(sellVals[i], maxVals[i]));
   }

   // Penalties
   SetLabelText(SES_PREFIX + "BrkBuyPen",  DoubleToString(g_score.buyPenalty,  1));
   SetLabelText(SES_PREFIX + "BrkSellPen", DoubleToString(g_score.sellPenalty, 1));
   color penColorBuy  = (g_score.buyPenalty  < -5.0) ? InpColorBad : InpColorText;
   color penColorSell = (g_score.sellPenalty < -5.0) ? InpColorBad : InpColorText;
   SetLabelColor(SES_PREFIX + "BrkBuyPen",  penColorBuy);
   SetLabelColor(SES_PREFIX + "BrkSellPen", penColorSell);

   // ── Active trade health ──
   if(g_health.active)
   {
      SetLabelText (SES_PREFIX + "ValTDir", g_health.direction);
      SetLabelColor(SES_PREFIX + "ValTDir",
                    g_health.direction == "BUY" ? clrDeepSkyBlue : clrOrange);
      SetLabelText (SES_PREFIX + "ValTExh", DoubleToString(g_health.exhaustion, 1));
      SetLabelColor(SES_PREFIX + "ValTExh", ExhaustionColor(g_health.exhaustion));
      SetLabelText (SES_PREFIX + "ValTSt",  g_health.state);
      SetLabelColor(SES_PREFIX + "ValTSt",  ExhaustionColor(g_health.exhaustion));
   }
   else
   {
      SetLabelText (SES_PREFIX + "ValTDir", "None");
      SetLabelColor(SES_PREFIX + "ValTDir", InpColorText);
      SetLabelText (SES_PREFIX + "ValTExh", "0.0");
      SetLabelColor(SES_PREFIX + "ValTExh", InpColorText);
      SetLabelText (SES_PREFIX + "ValTSt",  "Inactive");
      SetLabelColor(SES_PREFIX + "ValTSt",  InpColorText);
   }

   // ── Suggested zones ──
   if(g_atr > 0.0)
   {
      double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      int    digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      double stopLvl   = bid - g_score.suggestStop;
      double targetLvl = bid + g_score.suggestTarget;

      SetLabelText(SES_PREFIX + "ValStop",
                   DoubleToString(stopLvl, digits) +
                   " (dist=" + DoubleToString(g_score.suggestStop / g_atr, 1) + "R)");
      SetLabelText(SES_PREFIX + "ValTarget",
                   DoubleToString(targetLvl, digits) +
                   " (dist=" + DoubleToString(g_score.suggestTarget / g_atr, 1) + "R)");
   }
   else
   {
      SetLabelText(SES_PREFIX + "ValStop",   "---");
      SetLabelText(SES_PREFIX + "ValTarget", "---");
   }

   // ── Notes ──
   string notes = g_score.reasons;
   if(StringLen(notes) > 40) notes = StringSubstr(notes, 0, 40) + "…";
   SetLabelText(SES_PREFIX + "ValNotes", notes);
}

//--- Delete all SES_ objects from chart
void DeleteAllUIObjects()
{
   ObjectsDeleteAll(0, SES_PREFIX);
}

//+------------------------------------------------------------------+
//| SECTION 9 — UTILITY HELPERS                                      |
//+------------------------------------------------------------------+

//--- Safe CopyBuffer wrapper: checks handle validity and buffer count
bool SafeCopyBuffer(int handle, int bufferIndex, int start, int count, double &dst[])
{
   if(handle == INVALID_HANDLE) return false;
   if(CopyBuffer(handle, bufferIndex, start, count, dst) <= 0) return false;
   return true;
}

//--- Zero out a SScoreResult
void ZeroScoreResult(SScoreResult &r)
{
   r.buyTotal        = 0.0;
   r.sellTotal       = 0.0;
   r.buyPenalty      = 0.0;
   r.sellPenalty     = 0.0;
   r.buyClass        = "Avoid";
   r.sellClass       = "Avoid";
   r.reasons         = "";
   r.suggestStop     = 0.0;
   r.suggestTarget   = 0.0;

   r.buyComp.trend     = 0.0;
   r.buyComp.structure = 0.0;
   r.buyComp.location  = 0.0;
   r.buyComp.candle    = 0.0;
   r.buyComp.momentum  = 0.0;
   r.buyComp.rr        = 0.0;

   r.sellComp.trend     = 0.0;
   r.sellComp.structure = 0.0;
   r.sellComp.location  = 0.0;
   r.sellComp.candle    = 0.0;
   r.sellComp.momentum  = 0.0;
   r.sellComp.rr        = 0.0;
}

//--- Color based on total score
color ScoreColor(double score)
{
   if(score >= 60.0) return InpColorGood;
   if(score >= 40.0) return InpColorMedium;
   return InpColorBad;
}

//--- Color based on classification grade
color ClassColor(string cls)
{
   if(cls == "A+")   return InpColorGood;
   if(cls == "Good") return InpColorMedium;
   if(cls == "Weak") return InpColorMedium;
   return InpColorBad;
}

//--- Color for a component value relative to its maximum
color ComponentColor(double val, int maxVal)
{
   if(maxVal <= 0) return InpColorText;
   double pct = val / maxVal;
   if(pct >= 0.65) return InpColorGood;
   if(pct >= 0.35) return InpColorMedium;
   return InpColorBad;
}

//--- Color for exhaustion level
color ExhaustionColor(double ex)
{
   if(ex < 30.0) return InpColorGood;
   if(ex < 65.0) return InpColorMedium;
   return InpColorBad;
}

//--- Format a double to N decimal places with a sign prefix for display
string FormatSigned(double val, int digits)
{
   string s = DoubleToString(MathAbs(val), digits);
   return (val >= 0.0) ? ("+" + s) : ("-" + s);
}
//+------------------------------------------------------------------+
//| END OF FILE                                                       |
//+------------------------------------------------------------------+
