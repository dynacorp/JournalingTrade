//+------------------------------------------------------------------+
//|  SmartEdgeEA.mq5                                                 |
//|  TradeMind — Manual-Assist Trade Decision Support                |
//|  Version 1.0 — No auto-trading. Scoring + exhaustion only.       |
//+------------------------------------------------------------------+
#property copyright   "TradeMind"
#property version     "1.00"
#property description "SmartEdge EA — Manual-assist trade decision support. V1: no auto-trading."

// FIX-R1: Removed unused #include <Trade\Trade.mqh> and <Trade\PositionInfo.mqh>.
//         No CTrade/CPositionInfo instances exist; the includes only misled readers.

//+------------------------------------------------------------------+
//|  SECTION 1 — DEFINES                                             |
//+------------------------------------------------------------------+
#define SEA_PREFIX       "SEA_"
#define SEA_VERSION      "SmartEdge EA v1.0"
#define SEA_PANEL_X      15
#define SEA_PANEL_Y      25
#define SEA_PANEL_W      280
#define SEA_ROW_H        17
#define SEA_FONT         "Consolas"
#define SEA_FONT_SZ      8
#define SEA_FONT_SZ_SM   7

// Panel colours
#define C_BG             C'13,16,26'
#define C_HDR            C'26,31,50'
#define C_SEP            C'40,46,70'
#define C_TEXT           C'210,215,230'
#define C_DIM            C'100,108,130'
#define C_GOOD           C'80,200,120'
#define C_MED            C'240,180,60'
#define C_BAD            C'220,70,70'
#define C_BUY            C'70,140,255'
#define C_SELL           C'255,90,90'

//+------------------------------------------------------------------+
//|  SECTION 2 — ENUMS                                               |
//+------------------------------------------------------------------+
enum ENUM_TRADE_STATE
{
   TRADE_IDLE          = 0,
   TRADE_ACTIVE_BUY    = 1,
   TRADE_ACTIVE_SELL   = 2
};

enum ENUM_HEALTH_STATE
{
   HEALTH_HEALTHY               = 0,   // 0–14
   HEALTH_MILD_CAUTION          = 1,   // 15–29
   HEALTH_MOMENTUM_WEAKENING    = 2,   // 30–49
   HEALTH_EXHAUSTION_WATCH      = 3,   // 50–64
   HEALTH_EXIT_WATCH            = 4,   // 65–79
   HEALTH_REVERSAL_CONFIRMED    = 5    // 80–100
};

//+------------------------------------------------------------------+
//|  SECTION 3 — INPUTS                                              |
//+------------------------------------------------------------------+
sinput string _grp0 = "── Automation ──";
input bool   InpAutoTradeEnabled    = false;   // v2 placeholder
input bool   InpAutoDetectPosition  = false;   // v2 placeholder

sinput string _grp1 = "── Timeframes ──";
input ENUM_TIMEFRAMES InpHTF        = PERIOD_H4;   // Higher timeframe for bias
input int   InpSwingLookback        = 40;          // Bars to look back for swing pivots

sinput string _grp2 = "── Indicators ──";
input int   InpEMAPeriod   = 200;
input int   InpRSIPeriod   = 14;
input int   InpADXPeriod   = 14;
input int   InpATRPeriod   = 14;
input int   InpMACDFast    = 12;
input int   InpMACDSlow    = 26;
input int   InpMACDSignal  = 9;

sinput string _grp3 = "── Score Weights ──";
input int   InpWtTrend     = 20;   // Trend weight (max pts)
input int   InpWtStructure = 15;   // Structure weight
input int   InpWtLocation  = 20;   // Location weight
input int   InpWtCandle    = 15;   // Candle weight
input int   InpWtMomentum  = 15;   // Momentum weight
input int   InpWtRR        = 15;   // R:R Room weight

sinput string _grp4 = "── Penalty Thresholds ──";
input double InpChopADX      = 20.0;  // ADX below = chop penalty
input double InpExtremADX    = 15.0;  // ADX below = hard chop penalty
input double InpOverextMult  = 2.5;   // ATR multiples = overextension threshold
input double InpResistMult   = 0.5;   // ATR fraction = resistance-proximity threshold

sinput string _grp5 = "── R:R Thresholds ──";
input double InpRRWeak  = 1.5;  // R:R for Weak grade
input double InpRRGood  = 2.0;  // R:R for Good
input double InpRRExcl  = 3.0;  // R:R for A+

sinput string _grp6 = "── Alerts ──";
input bool   InpPushEnabled   = false;
input bool   InpAlertOnState  = false;

sinput string _grp7 = "── Panel Colours ──";
input color  InpColorBG     = C_BG;
input color  InpColorHeader = C_HDR;

//+------------------------------------------------------------------+
//|  SECTION 4 — STRUCTS                                             |
//+------------------------------------------------------------------+
struct SComponentScores
{
   // No string members — ZeroMemory is safe on this sub-struct.
   double trend, structure, location, candle, momentum, rr;
};

struct SScoreResult
{
   double           buyTotal,  sellTotal;
   SComponentScores buyComp,   sellComp;
   double           buyPenalty, sellPenalty;
   string           buyClass,  sellClass;   // "A+", "Good", "Weak", "Avoid"
   string           buyLog,    sellLog;     // penalty reason strings
   double           suggestStop, suggestTarget;
};

struct STradeRecord
{
   ENUM_TRADE_STATE   tradeState;
   double             entryPrice;
   datetime           entryTime;
   int                barsHeld;
   double             exhaustion;
   ENUM_HEALTH_STATE  healthState;
   string             healthText;          // string field — must not ZeroMemory this struct
   ENUM_HEALTH_STATE  prevHealthState;
   double exh_body, exh_wick, exh_divergence;
   double exh_stall, exh_atr, exh_pattern, exh_trendBonus, exh_raw;
   bool alertFiredPartial, alertFiredFull, alertFiredReversal;
   int    barsSinceNewExtreme;
   double extremePrice;
   double entryATR;
   // v2 reserved
   double stopLoss, takeProfit;
   ulong  positionTicket;
};

//+------------------------------------------------------------------+
//|  SECTION 5 — GLOBALS                                             |
//+------------------------------------------------------------------+
string         g_prefix      = SEA_PREFIX;
SScoreResult   g_score;
STradeRecord   g_trade;
double         g_atr         = 0.0;
datetime       g_lastBarTime = 0;
bool           g_scoreValid  = false;  // FIX-R4: explicit flag replaces fragile string comparison

// Indicator handles
int g_hEMA_CTF  = INVALID_HANDLE;
int g_hEMA_HTF  = INVALID_HANDLE;
int g_hRSI      = INVALID_HANDLE;
int g_hADX      = INVALID_HANDLE;
int g_hATR      = INVALID_HANDLE;
int g_hMACD     = INVALID_HANDLE;
int g_hRSI_HTF  = INVALID_HANDLE;
// FIX-R6: g_hADX_HTF removed — handle was created and released but its buffer
//         was never read anywhere in scoring logic. HTF bias uses RSI only.

// Swing pivot cache (index 1 = most recent confirmed pivot, 2 = previous)
double g_pivHigh1 = 0, g_pivHigh2 = 0;
double g_pivLow1  = 0, g_pivLow2  = 0;

//+------------------------------------------------------------------+
//|  SECTION 6 — STRUCT RESET HELPERS                                |
//+------------------------------------------------------------------+
// FIX-R2: Replace ZeroMemory on string-containing structs with explicit resets.
// ZeroMemory zeroes the raw string descriptor pointer, which corrupts the heap
// when MQL5 later tries to free or reassign the string slot.

void ResetScore()
{
   g_score.buyTotal      = 0.0;  g_score.sellTotal    = 0.0;
   g_score.buyPenalty    = 0.0;  g_score.sellPenalty  = 0.0;
   g_score.buyClass      = "Avoid";  g_score.sellClass = "Avoid";
   g_score.buyLog        = "";   g_score.sellLog      = "";
   g_score.suggestStop   = 0.0;  g_score.suggestTarget = 0.0;
   ZeroMemory(g_score.buyComp);   // SComponentScores has no strings — safe
   ZeroMemory(g_score.sellComp);
}

void ResetTrade()
{
   g_trade.tradeState          = TRADE_IDLE;
   g_trade.entryPrice          = 0.0;
   g_trade.entryTime           = 0;
   g_trade.barsHeld            = 0;
   g_trade.exhaustion          = 0.0;
   g_trade.healthState         = HEALTH_HEALTHY;
   g_trade.healthText          = "Healthy Trend";   // explicit string assign
   g_trade.prevHealthState     = HEALTH_HEALTHY;
   g_trade.exh_body            = 0.0;  g_trade.exh_wick      = 0.0;
   g_trade.exh_divergence      = 0.0;  g_trade.exh_stall     = 0.0;
   g_trade.exh_atr             = 0.0;  g_trade.exh_pattern   = 0.0;
   g_trade.exh_trendBonus      = 0.0;  g_trade.exh_raw       = 0.0;
   g_trade.alertFiredPartial   = false;
   g_trade.alertFiredFull      = false;
   g_trade.alertFiredReversal  = false;
   g_trade.barsSinceNewExtreme = 0;
   g_trade.extremePrice        = 0.0;
   g_trade.entryATR            = 0.0;
   g_trade.stopLoss            = 0.0;
   g_trade.takeProfit          = 0.0;
   g_trade.positionTicket      = 0;
}

//+------------------------------------------------------------------+
//|  SECTION 7 — OnInit                                              |
//+------------------------------------------------------------------+
int OnInit()
{
   g_hEMA_CTF = iMA (_Symbol, _Period,  InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_hEMA_HTF = iMA (_Symbol, InpHTF,  InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_hRSI     = iRSI(_Symbol, _Period, InpRSIPeriod, PRICE_CLOSE);
   g_hADX     = iADX(_Symbol, _Period, InpADXPeriod);
   g_hATR     = iATR(_Symbol, _Period, InpATRPeriod);
   g_hMACD    = iMACD(_Symbol, _Period, InpMACDFast, InpMACDSlow, InpMACDSignal, PRICE_CLOSE);
   g_hRSI_HTF = iRSI(_Symbol, InpHTF,  InpRSIPeriod, PRICE_CLOSE);

   // FIX-R5: All 7 handles validated (previously only 6 were checked;
   //         g_hRSI_HTF was silently allowed to be INVALID_HANDLE).
   if(g_hEMA_CTF == INVALID_HANDLE || g_hEMA_HTF == INVALID_HANDLE ||
      g_hRSI     == INVALID_HANDLE || g_hADX     == INVALID_HANDLE ||
      g_hATR     == INVALID_HANDLE || g_hMACD    == INVALID_HANDLE ||
      g_hRSI_HTF == INVALID_HANDLE)
   {
      Print("SmartEdge: Failed to create indicator handles. Check symbol/period.");
      return INIT_FAILED;
   }

   // FIX-R2: Use explicit reset functions instead of ZeroMemory on structs
   //         that contain string members.
   ResetScore();
   ResetTrade();
   g_scoreValid = false;

   EventSetMillisecondTimer(500);

   BuildPanel();
   RefreshPanel();
   ChartRedraw();

   Print("SmartEdge EA v1.0 initialised on ", _Symbol, " ", EnumToString(_Period));
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//|  SECTION 8 — OnDeinit                                            |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   DeleteAllUIObjects();

   // FIX-R6: g_hADX_HTF handle removed — was created and released but never used.
   if(g_hEMA_CTF != INVALID_HANDLE) IndicatorRelease(g_hEMA_CTF);
   if(g_hEMA_HTF != INVALID_HANDLE) IndicatorRelease(g_hEMA_HTF);
   if(g_hRSI     != INVALID_HANDLE) IndicatorRelease(g_hRSI);
   if(g_hADX     != INVALID_HANDLE) IndicatorRelease(g_hADX);
   if(g_hATR     != INVALID_HANDLE) IndicatorRelease(g_hATR);
   if(g_hMACD    != INVALID_HANDLE) IndicatorRelease(g_hMACD);
   if(g_hRSI_HTF != INVALID_HANDLE) IndicatorRelease(g_hRSI_HTF);

   ChartRedraw();
}

//+------------------------------------------------------------------+
//|  SECTION 9 — OnTick                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   datetime barTime = iTime(_Symbol, _Period, 0);
   if(barTime == g_lastBarTime) return;
   g_lastBarTime = barTime;
   OnNewBar();
}

//--- Called once per confirmed new bar
void OnNewBar()
{
   double atrBuf[];
   ArraySetAsSeries(atrBuf, true);
   if(CopyBuffer(g_hATR, 0, 1, 1, atrBuf) == 1)
      g_atr = atrBuf[0];

   RefreshSwingPivots();

   if(g_trade.tradeState != TRADE_IDLE)
   {
      g_trade.barsHeld++;
      TrackExtremePrice();
      RunExhaustionEngine();
      FireAlerts();
   }

   RefreshPanel();
   ChartRedraw();
}

//+------------------------------------------------------------------+
//|  SECTION 10 — OnTimer                                            |
//+------------------------------------------------------------------+
void OnTimer()
{
   RefreshPanel();
   ChartRedraw();
}

//+------------------------------------------------------------------+
//|  SECTION 11 — OnChartEvent                                       |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long& lparam, const double& dparam, const string& sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
      HandleButtonClick(sparam);
}

//+------------------------------------------------------------------+
//|  SECTION 12 — BUTTON HANDLER                                     |
//+------------------------------------------------------------------+
void HandleButtonClick(const string name)
{
   ObjectSetInteger(0, name, OBJPROP_STATE, false);   // reset toggle immediately

   if(name == g_prefix + "BTN_BUY_EVAL")
   {
      RunFullScoring(true);
      RefreshPanel();
      ChartRedraw();
   }
   else if(name == g_prefix + "BTN_SELL_EVAL")
   {
      RunFullScoring(false);
      RefreshPanel();
      ChartRedraw();
   }
   else if(name == g_prefix + "BTN_SET_BUY")
   {
      SetActiveTrade(TRADE_ACTIVE_BUY);
      RefreshPanel();
      ChartRedraw();
   }
   else if(name == g_prefix + "BTN_SET_SELL")
   {
      SetActiveTrade(TRADE_ACTIVE_SELL);
      RefreshPanel();
      ChartRedraw();
   }
   else if(name == g_prefix + "BTN_CLEAR")
   {
      ClearActiveTrade();
      RefreshPanel();
      ChartRedraw();
   }
}

//+------------------------------------------------------------------+
//|  SECTION 13 — TRADE STATE MACHINE                                |
//+------------------------------------------------------------------+
void SetActiveTrade(ENUM_TRADE_STATE dir)
{
   // FIX-R2: Use ResetTrade() instead of ZeroMemory(g_trade).
   //         g_trade.healthText is a string — ZeroMemory on it corrupts the heap.
   ResetTrade();
   g_trade.tradeState          = dir;
   g_trade.entryPrice          = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   g_trade.entryTime           = TimeCurrent();
   g_trade.entryATR            = g_atr;
   g_trade.extremePrice        = g_trade.entryPrice;
   g_trade.stopLoss            = g_score.suggestStop;
   g_trade.takeProfit          = g_score.suggestTarget;

   Print("SmartEdge: Active trade — ",
         (dir == TRADE_ACTIVE_BUY ? "BUY" : "SELL"),
         " @ ", DoubleToString(g_trade.entryPrice, _Digits));
}

void ClearActiveTrade()
{
   g_trade.tradeState  = TRADE_IDLE;
   g_trade.healthState = HEALTH_HEALTHY;
   g_trade.healthText  = "Healthy Trend";
   g_trade.barsHeld    = 0;
   g_trade.exhaustion  = 0;
   Print("SmartEdge: Active trade cleared.");
}

void TrackExtremePrice()
{
   double hi[], lo[];
   ArraySetAsSeries(hi, true); ArraySetAsSeries(lo, true);
   if(CopyHigh(_Symbol, _Period, 1, 1, hi) < 1) return;
   if(CopyLow (_Symbol, _Period, 1, 1, lo) < 1) return;

   bool newExtreme = false;
   if(g_trade.tradeState == TRADE_ACTIVE_BUY)
   {
      if(hi[0] > g_trade.extremePrice) { g_trade.extremePrice = hi[0]; newExtreme = true; }
   }
   else
   {
      if(lo[0] < g_trade.extremePrice) { g_trade.extremePrice = lo[0]; newExtreme = true; }
   }

   if(newExtreme) g_trade.barsSinceNewExtreme = 0;
   else           g_trade.barsSinceNewExtreme++;
}

//+------------------------------------------------------------------+
//|  SECTION 14 — SCORING ENGINE                                     |
//+------------------------------------------------------------------+

// FIX-R3: g_scoreValid is set false at entry and true only on successful
//         completion of all CopyBuffer calls. If any copy fails, the panel
//         retains the last valid score rather than displaying garbage from a
//         half-updated g_score struct.

void RunFullScoring(bool evalBuy)
{
   g_scoreValid = false;   // FIX-R3: invalidate until we complete cleanly

   // ── Fetch indicator buffers (start=1 skips live bar 0) ───────
   // FIX-R7/R9/R10: Reduced array sizes to the minimum actually needed.
   //                CopyBuffer count=N allocates work — over-copying wastes CPU.
   double emaCTF[], emaHTF[], rsi[], adx[], atrBuf[];
   double macdMain[], macdSig[], rsiHTF[];
   double open3[], high3[], low3[], close3[];

   ArraySetAsSeries(emaCTF,   true); ArraySetAsSeries(emaHTF,   true);
   ArraySetAsSeries(rsi,      true); ArraySetAsSeries(adx,      true);
   ArraySetAsSeries(atrBuf,   true); ArraySetAsSeries(macdMain, true);
   ArraySetAsSeries(macdSig,  true); ArraySetAsSeries(rsiHTF,   true);
   ArraySetAsSeries(open3,    true); ArraySetAsSeries(high3,   true);
   ArraySetAsSeries(low3,     true); ArraySetAsSeries(close3,  true);

   // Diagnostic logging: each failed copy prints to Experts tab.
   // Once working, these can be removed or left — they only fire on failure.
   int bc_ema_ctf = BarsCalculated(g_hEMA_CTF);
   int bc_ema_htf = BarsCalculated(g_hEMA_HTF);
   int bc_rsi     = BarsCalculated(g_hRSI);
   int bc_adx     = BarsCalculated(g_hADX);
   int bc_atr     = BarsCalculated(g_hATR);
   int bc_macd    = BarsCalculated(g_hMACD);
   int bc_rsi_htf = BarsCalculated(g_hRSI_HTF);
   Print("SmartEdge Diag | BarsCalc EMA_CTF=", bc_ema_ctf,
         " EMA_HTF=", bc_ema_htf, " RSI=", bc_rsi,
         " ADX=", bc_adx, " ATR=", bc_atr,
         " MACD=", bc_macd, " RSI_HTF=", bc_rsi_htf);

   if(CopyBuffer(g_hEMA_CTF, 0, 1, 1, emaCTF)   < 1) { Print("SmartEdge: EMA_CTF copy failed err=",GetLastError()); return; }
   if(CopyBuffer(g_hEMA_HTF, 0, 1, 1, emaHTF)   < 1) { Print("SmartEdge: EMA_HTF copy failed err=",GetLastError()); return; }
   if(CopyBuffer(g_hRSI,     0, 1, 1, rsi)       < 1) { Print("SmartEdge: RSI copy failed err=",GetLastError()); return; }
   if(CopyBuffer(g_hADX,     0, 1, 1, adx)       < 1) { Print("SmartEdge: ADX copy failed err=",GetLastError()); return; }
   if(CopyBuffer(g_hATR,     0, 1, 1, atrBuf)    < 1) { Print("SmartEdge: ATR copy failed err=",GetLastError()); return; }
   if(CopyBuffer(g_hMACD,    0, 1, 1, macdMain)  < 1) { Print("SmartEdge: MACD main copy failed err=",GetLastError()); return; }
   if(CopyBuffer(g_hMACD,    1, 1, 1, macdSig)   < 1) { Print("SmartEdge: MACD sig copy failed err=",GetLastError()); return; }
   if(CopyBuffer(g_hRSI_HTF, 0, 1, 1, rsiHTF)   < 1) { Print("SmartEdge: RSI_HTF copy failed err=",GetLastError()); return; }
   if(CopyOpen (_Symbol, _Period, 1, 3, open3)   < 3) { Print("SmartEdge: CopyOpen failed err=",GetLastError()); return; }
   if(CopyHigh (_Symbol, _Period, 1, 3, high3)   < 3) { Print("SmartEdge: CopyHigh failed err=",GetLastError()); return; }
   if(CopyLow  (_Symbol, _Period, 1, 3, low3)    < 3) { Print("SmartEdge: CopyLow failed err=",GetLastError()); return; }
   if(CopyClose(_Symbol, _Period, 1, 3, close3)  < 3) { Print("SmartEdge: CopyClose failed err=",GetLastError()); return; }

   // All copies succeeded — safe to update g_score
   g_atr = atrBuf[0];
   double price    = close3[0];
   double adxVal   = adx[0];
   double macdHist = macdMain[0] - macdSig[0];   // histogram = main - signal

   // ── Component scores — BUY ────────────────────────────────────
   g_score.buyComp.trend     = ScoreTrend     (price, emaCTF[0], emaHTF[0], true);
   g_score.buyComp.structure = ScoreStructure (true);
   g_score.buyComp.location  = ScoreLocation  (price, true);
   g_score.buyComp.candle    = ScoreCandle    (open3[0], high3[0], low3[0], close3[0], true);
   g_score.buyComp.momentum  = ScoreMomentum  (rsi[0], macdHist, true);
   g_score.buyComp.rr        = ScoreRR        (price, true);

   // ── Component scores — SELL ───────────────────────────────────
   g_score.sellComp.trend     = ScoreTrend     (price, emaCTF[0], emaHTF[0], false);
   g_score.sellComp.structure = ScoreStructure (false);
   g_score.sellComp.location  = ScoreLocation  (price, false);
   g_score.sellComp.candle    = ScoreCandle    (open3[0], high3[0], low3[0], close3[0], false);
   g_score.sellComp.momentum  = ScoreMomentum  (rsi[0], macdHist, false);
   g_score.sellComp.rr        = ScoreRR        (price, false);

   // ── Penalties ─────────────────────────────────────────────────
   g_score.buyPenalty  = 0.0;  g_score.buyLog  = "";
   g_score.sellPenalty = 0.0;  g_score.sellLog = "";

   // Chop (both directions)
   if(adxVal < InpExtremADX)
   {
      g_score.buyPenalty  -= 20; g_score.buyLog  += "HardChop(-20) ";
      g_score.sellPenalty -= 20; g_score.sellLog += "HardChop(-20) ";
   }
   else if(adxVal < InpChopADX)
   {
      g_score.buyPenalty  -= 12; g_score.buyLog  += "Chop(-12) ";
      g_score.sellPenalty -= 12; g_score.sellLog += "Chop(-12) ";
   }

   // Overextension (directional)
   double bOvx = PenaltyOverextension(price, true);
   double sOvx = PenaltyOverextension(price, false);
   if(bOvx < 0) { g_score.buyPenalty  += bOvx; g_score.buyLog  += "Overext(-10) "; }
   if(sOvx < 0) { g_score.sellPenalty += sOvx; g_score.sellLog += "Overext(-10) "; }

   // Resistance / support proximity
   double bPrx = PenaltyResistanceProximity(price, g_pivHigh1, g_atr, true);
   double sPrx = PenaltyResistanceProximity(price, g_pivLow1,  g_atr, false);
   if(bPrx < 0) { g_score.buyPenalty  += bPrx; g_score.buyLog  += "ResistClose(-12) "; }
   if(sPrx < 0) { g_score.sellPenalty += sPrx; g_score.sellLog += "SupportClose(-12) "; }

   // HTF RSI conflict
   double htfRSI = rsiHTF[0];
   if(htfRSI < 45) { g_score.buyPenalty  -= 8; g_score.buyLog  += "HTFConflict(-8) "; }
   if(htfRSI > 55) { g_score.sellPenalty -= 8; g_score.sellLog += "HTFConflict(-8) "; }

   // ── Totals ─────────────────────────────────────────────────────
   double bRaw = g_score.buyComp.trend + g_score.buyComp.structure + g_score.buyComp.location +
                 g_score.buyComp.candle + g_score.buyComp.momentum + g_score.buyComp.rr;
   double sRaw = g_score.sellComp.trend + g_score.sellComp.structure + g_score.sellComp.location +
                 g_score.sellComp.candle + g_score.sellComp.momentum + g_score.sellComp.rr;

   g_score.buyTotal  = MathMax(0, MathMin(100, bRaw + g_score.buyPenalty));
   g_score.sellTotal = MathMax(0, MathMin(100, sRaw + g_score.sellPenalty));
   g_score.buyClass  = ClassifyScore(g_score.buyTotal);
   g_score.sellClass = ClassifyScore(g_score.sellTotal);

   // ── Stop / Target suggestions ─────────────────────────────────
   if(evalBuy)
   {
      g_score.suggestStop   = (g_pivLow1  > 0) ? g_pivLow1  : price - 2.0 * g_atr;
      g_score.suggestTarget = (g_pivHigh2 > 0) ? g_pivHigh2 : price + 4.0 * g_atr;
   }
   else
   {
      g_score.suggestStop   = (g_pivHigh1 > 0) ? g_pivHigh1 : price + 2.0 * g_atr;
      g_score.suggestTarget = (g_pivLow2  > 0) ? g_pivLow2  : price - 4.0 * g_atr;
   }

   g_scoreValid = true;   // FIX-R3: only set true on full successful completion
}

//--- Trend component: max InpWtTrend pts
double ScoreTrend(double price, double emaCTF, double emaHTF, bool isBuy)
{
   double htf = 0, ctf = 0;
   if(isBuy)  { if(price > emaHTF) htf = 1.0; if(price > emaCTF) ctf = 1.0; }
   else       { if(price < emaHTF) htf = 1.0; if(price < emaCTF) ctf = 1.0; }
   return InpWtTrend * (0.60 * htf + 0.40 * ctf);
}

//--- Structure component: HH+HL (bull) or LH+LL (bear)
double ScoreStructure(bool isBuy)
{
   if(g_pivHigh1 == 0 || g_pivHigh2 == 0 || g_pivLow1 == 0 || g_pivLow2 == 0)
      return 0;
   if(isBuy)
   {
      bool hh = (g_pivHigh1 > g_pivHigh2);
      bool hl = (g_pivLow1  > g_pivLow2);
      if(hh && hl) return InpWtStructure;
      if(hh || hl) return InpWtStructure * 0.5;
   }
   else
   {
      bool lh = (g_pivHigh1 < g_pivHigh2);
      bool ll = (g_pivLow1  < g_pivLow2);
      if(lh && ll) return InpWtStructure;
      if(lh || ll) return InpWtStructure * 0.5;
   }
   return 0;
}

//--- Location component: proximity to swing support/resistance
double ScoreLocation(double price, bool isBuy)
{
   double ref = isBuy ? g_pivLow1 : g_pivHigh1;
   if(ref == 0 || g_atr == 0) return 0;
   double dist = MathAbs(price - ref) / g_atr;
   if(dist <= 0.5) return InpWtLocation;
   if(dist <= 1.0) return InpWtLocation * 0.75;
   if(dist <= 1.5) return InpWtLocation * 0.50;
   if(dist <= 2.5) return InpWtLocation * 0.25;
   return 0;
}

//--- Candle component: body ratio, direction, rejection wick
double ScoreCandle(double open, double high, double low, double close, bool isBuy)
{
   double range = high - low;
   if(range == 0) return 0;
   double body      = MathAbs(close - open);
   double bodyRatio = body / range;
   double upperWick = high - MathMax(open, close);
   double lowerWick = MathMin(open, close) - low;
   double pts       = 0;

   if(bodyRatio >= 0.6)      pts += InpWtCandle * 0.4;
   else if(bodyRatio >= 0.4) pts += InpWtCandle * 0.2;

   if(isBuy  && close > open) pts += InpWtCandle * 0.3;
   if(!isBuy && close < open) pts += InpWtCandle * 0.3;

   if(isBuy  && lowerWick > 0.5 * range && bodyRatio < 0.4) pts += InpWtCandle * 0.3;
   if(!isBuy && upperWick > 0.5 * range && bodyRatio < 0.4) pts += InpWtCandle * 0.3;

   return MathMin(InpWtCandle, pts);
}

//--- Momentum component: RSI 60% + MACD histogram 40%
double ScoreMomentum(double rsi, double macdHist, bool isBuy)
{
   double rsiPts = 0, macdPts = 0;
   if(isBuy)
   {
      if(rsi > 55)      rsiPts = 1.0;
      else if(rsi > 50) rsiPts = 0.5;
      if(macdHist > 0)  macdPts = 1.0;
   }
   else
   {
      if(rsi < 45)      rsiPts = 1.0;
      else if(rsi < 50) rsiPts = 0.5;
      if(macdHist < 0)  macdPts = 1.0;
   }
   return InpWtMomentum * (0.60 * rsiPts + 0.40 * macdPts);
}

//--- R:R Room component
double ScoreRR(double price, bool isBuy)
{
   double stop, target;
   if(isBuy)
   {
      stop   = (g_pivLow1  > 0) ? g_pivLow1  : price - 2.0 * g_atr;
      target = (g_pivHigh2 > 0) ? g_pivHigh2 : price + 4.0 * g_atr;
   }
   else
   {
      stop   = (g_pivHigh1 > 0) ? g_pivHigh1 : price + 2.0 * g_atr;
      target = (g_pivLow2  > 0) ? g_pivLow2  : price - 4.0 * g_atr;
   }
   double risk   = MathAbs(price - stop);
   double reward = MathAbs(target - price);
   if(risk == 0) return 0;
   double rr = reward / risk;
   if(rr >= InpRRExcl) return InpWtRR;
   if(rr >= InpRRGood) return InpWtRR * 0.75;
   if(rr >= InpRRWeak) return InpWtRR * 0.40;
   return 0;
}

//--- Penalty: price overextended beyond swing level
double PenaltyOverextension(double price, bool isBuy)
{
   double ref = isBuy ? g_pivHigh1 : g_pivLow1;
   if(ref == 0 || g_atr == 0) return 0;
   double dist = MathAbs(price - ref) / g_atr;
   return (dist > InpOverextMult) ? -10.0 : 0.0;
}

//--- Penalty: price too close to opposing swing level (resistance for buys, support for sells)
double PenaltyResistanceProximity(double price, double level, double atr, bool isBuy)
{
   if(level == 0 || atr == 0) return 0;
   double dist     = MathAbs(level - price) / atr;
   bool   tooClose = isBuy ? (level > price) : (level < price);
   if(dist <= InpResistMult && tooClose) return -12.0;
   return 0;
}

//--- Score → grade string
string ClassifyScore(double total)
{
   if(total >= 80) return "A+";
   if(total >= 65) return "Good";
   if(total >= 45) return "Weak";
   return "Avoid";
}

//+------------------------------------------------------------------+
//|  SECTION 15 — SWING PIVOT CACHE                                  |
//+------------------------------------------------------------------+
void RefreshSwingPivots()
{
   int lb = InpSwingLookback;
   double hi[], lo[];
   ArraySetAsSeries(hi, true);
   ArraySetAsSeries(lo, true);

   // Note: if fewer than lb bars are loaded, pivots silently retain
   // their previous values. This is safe on established charts.
   if(CopyHigh(_Symbol, _Period, 1, lb, hi) < lb) return;
   if(CopyLow (_Symbol, _Period, 1, lb, lo) < lb) return;

   // Pivot detection: 2-bar wing (bar i must be extreme vs ±1 and ±2 neighbours)
   double fHigh[2] = {0, 0};
   double fLow[2]  = {0, 0};
   int    hCnt = 0, lCnt = 0;
   int    wing = 2;

   // Index 0 = most recent closed bar (ArraySetAsSeries=true).
   // Scan from wing inward so we don't access out-of-range neighbours.
   for(int i = wing; i < lb - wing && (hCnt < 2 || lCnt < 2); i++)
   {
      if(hCnt < 2)
      {
         bool isPH = true;
         for(int w = 1; w <= wing && isPH; w++)
            if(hi[i] <= hi[i - w] || hi[i] <= hi[i + w]) isPH = false;
         if(isPH) { fHigh[hCnt] = hi[i]; hCnt++; }
      }
      if(lCnt < 2)
      {
         bool isPL = true;
         for(int w = 1; w <= wing && isPL; w++)
            if(lo[i] >= lo[i - w] || lo[i] >= lo[i + w]) isPL = false;
         if(isPL) { fLow[lCnt] = lo[i]; lCnt++; }
      }
   }

   if(hCnt >= 1) g_pivHigh1 = fHigh[0];
   if(hCnt >= 2) g_pivHigh2 = fHigh[1];
   if(lCnt >= 1) g_pivLow1  = fLow[0];
   if(lCnt >= 2) g_pivLow2  = fLow[1];
}

//+------------------------------------------------------------------+
//|  SECTION 16 — EXHAUSTION ENGINE                                  |
//+------------------------------------------------------------------+
void RunExhaustionEngine()
{
   if(g_trade.tradeState == TRADE_IDLE) return;
   bool isBuy = (g_trade.tradeState == TRADE_ACTIVE_BUY);

   const int NB = 12;
   double op[], hi[], lo[], cl[], rsi[], atrB[], adxB[];

   ArraySetAsSeries(op,   true); ArraySetAsSeries(hi,   true);
   ArraySetAsSeries(lo,   true); ArraySetAsSeries(cl,   true);
   ArraySetAsSeries(rsi,  true); ArraySetAsSeries(adxB, true);
   ArraySetAsSeries(atrB, true);

   if(CopyOpen (_Symbol, _Period, 1, NB, op)   < NB) return;
   if(CopyHigh (_Symbol, _Period, 1, NB, hi)   < NB) return;
   if(CopyLow  (_Symbol, _Period, 1, NB, lo)   < NB) return;
   if(CopyClose(_Symbol, _Period, 1, NB, cl)   < NB) return;
   if(CopyBuffer(g_hRSI, 0, 1, 6, rsi)         <  6) return;
   if(CopyBuffer(g_hADX, 0, 1, 1, adxB)        <  1) return;  // FIX-R8: was count=6
   if(CopyBuffer(g_hATR, 0, 1, 8, atrB)        <  8) return;

   // ── C1: Body Shrinkage 25 pts ─────────────────────────────────
   double avg3 = 0, avg10 = 0;
   for(int i = 0; i < 3;  i++) avg3  += MathAbs(cl[i] - op[i]);
   for(int i = 0; i < 10; i++) avg10 += MathAbs(cl[i] - op[i]);
   avg3 /= 3.0; avg10 /= 10.0;
   double bodyRat = (avg10 > 0) ? avg3 / avg10 : 1.0;
   double c1 = 0;
   if(bodyRat < 0.40)       c1 = 25;
   else if(bodyRat < 0.65)  c1 = 15;
   else if(bodyRat < 0.80)  c1 = 8;

   // ── C2: Adverse Wick 20 pts ───────────────────────────────────
   double rng0 = hi[0] - lo[0];
   double c2   = 0;
   if(rng0 > 0)
   {
      double adverseW = isBuy ? (hi[0] - MathMax(op[0], cl[0])) :
                                (MathMin(op[0], cl[0]) - lo[0]);
      double wickRat  = adverseW / rng0;
      if(wickRat > 0.55)      c2 = 20;
      else if(wickRat > 0.35) c2 = 10;
   }

   // ── C3: RSI Divergence 30 pts ─────────────────────────────────
   double c3 = 0;
   if(g_trade.barsHeld >= 5)
   {
      double pNow  = isBuy ? hi[0] : lo[0];
      double pPrev = isBuy ? hi[4] : lo[4];
      bool   newEx = isBuy ? (pNow > pPrev) : (pNow < pPrev);
      bool   rsiOk = isBuy ? (rsi[0] > rsi[4]) : (rsi[0] < rsi[4]);
      if(newEx && !rsiOk) c3 = 30;
   }

   // ── C4: Structural Stall 15 pts ───────────────────────────────
   int    bsne = g_trade.barsSinceNewExtreme;
   double c4   = 0;
   if(bsne >= 8)      c4 = 15;
   else if(bsne >= 5) c4 = 10;
   else if(bsne >= 3) c4 = 5;

   // ── C5: ATR Contraction 10 pts ────────────────────────────────
   double c5 = 0;
   if(atrB[5] > 0 && (atrB[0] / atrB[5]) < 0.65) c5 = 10;

   // ── C6: Reversal Candle 10 pts ────────────────────────────────
   double rng1 = hi[0] - lo[0];
   double c6   = 0;
   if(rng1 > 0)
   {
      double body0  = MathAbs(cl[0] - op[0]);
      double bRat   = body0 / rng1;
      double upperW = hi[0] - MathMax(op[0], cl[0]);
      double lowerW = MathMin(op[0], cl[0]) - lo[0];
      double prevRng = hi[1] - lo[1];
      bool   engulf  = (body0 > prevRng * 1.1);

      if(isBuy)
      {
         bool shootingStar = (upperW > 0.55 * rng1) && (bRat < 0.3);
         if(shootingStar || (cl[0] < op[0] && engulf)) c6 = 10;
         else if(cl[0] < op[0])                        c6 = 5;
      }
      else
      {
         bool hammer = (lowerW > 0.55 * rng1) && (bRat < 0.3);
         if(hammer || (cl[0] > op[0] && engulf))       c6 = 10;
         else if(cl[0] > op[0])                        c6 = 5;
      }
   }

   double rawScore = c1 + c2 + c3 + c4 + c5 + c6;

   // ── Trend Strength Suppression (up to -25 pts) ───────────────
   double adxNow   = adxB[0];
   double suppress = 0;

   if(adxNow > 35)      suppress += 10;
   else if(adxNow > 25) suppress += 5;

   int consec = 0;
   for(int i = 0; i < 5; i++)
   {
      bool trendCl = isBuy ? (cl[i] > op[i]) : (cl[i] < op[i]);
      if(trendCl) consec++;
      else break;
   }
   if(consec >= 4)      suppress += 10;
   else if(consec >= 2) suppress += 5;

   if(isBuy  && rsi[0] > 65) suppress += 5;
   if(!isBuy && rsi[0] < 35) suppress += 5;
   if(bsne <= 1)              suppress += 5;

   suppress = MathMin(25, suppress);

   double finalScore = rawScore - suppress;

   // Floor protection: anti-false-exit on early bars
   if(g_trade.barsHeld < 3)      finalScore = MathMin(finalScore, 30);
   else if(g_trade.barsHeld < 5) finalScore = MathMin(finalScore, 50);

   finalScore = MathMax(0, MathMin(100, finalScore));

   // ── Store component breakdown ─────────────────────────────────
   g_trade.exh_body        = c1;
   g_trade.exh_wick        = c2;
   g_trade.exh_divergence  = c3;
   g_trade.exh_stall       = c4;
   g_trade.exh_atr         = c5;
   g_trade.exh_pattern     = c6;
   g_trade.exh_trendBonus  = -suppress;
   g_trade.exh_raw         = rawScore;
   g_trade.exhaustion      = finalScore;

   // ── Health state ─────────────────────────────────────────────
   g_trade.prevHealthState = g_trade.healthState;
   if     (finalScore >= 80) { g_trade.healthState = HEALTH_REVERSAL_CONFIRMED;  g_trade.healthText = "Reversal Confirmed"; }
   else if(finalScore >= 65) { g_trade.healthState = HEALTH_EXIT_WATCH;          g_trade.healthText = "Exit Watch";          }
   else if(finalScore >= 50) { g_trade.healthState = HEALTH_EXHAUSTION_WATCH;    g_trade.healthText = "Exhaustion Watch";    }
   else if(finalScore >= 30) { g_trade.healthState = HEALTH_MOMENTUM_WEAKENING;  g_trade.healthText = "Momentum Weakening";  }
   else if(finalScore >= 15) { g_trade.healthState = HEALTH_MILD_CAUTION;        g_trade.healthText = "Mild Caution";        }
   else                      { g_trade.healthState = HEALTH_HEALTHY;             g_trade.healthText = "Healthy Trend";       }
}

//--- Fire alerts on health escalation (each level fires once per trade)
void FireAlerts()
{
   if(!InpAlertOnState && !InpPushEnabled) return;
   ENUM_HEALTH_STATE hs = g_trade.healthState;

   if(hs >= HEALTH_EXHAUSTION_WATCH && !g_trade.alertFiredPartial)
   {
      string m = "SmartEdge [" + _Symbol + "]: Exhaustion Watch — consider partial exit";
      if(InpAlertOnState) Alert(m);
      if(InpPushEnabled)  SendNotification(m);
      g_trade.alertFiredPartial = true;
   }
   if(hs >= HEALTH_EXIT_WATCH && !g_trade.alertFiredFull)
   {
      string m = "SmartEdge [" + _Symbol + "]: Exit Watch — full exit recommended";
      if(InpAlertOnState) Alert(m);
      if(InpPushEnabled)  SendNotification(m);
      g_trade.alertFiredFull = true;
   }
   if(hs >= HEALTH_REVERSAL_CONFIRMED && !g_trade.alertFiredReversal)
   {
      string m = "SmartEdge [" + _Symbol + "]: Reversal Confirmed — exit NOW";
      if(InpAlertOnState) Alert(m);
      if(InpPushEnabled)  SendNotification(m);
      g_trade.alertFiredReversal = true;
   }
}

//+------------------------------------------------------------------+
//|  SECTION 17 — UI PRIMITIVE HELPERS                               |
//+------------------------------------------------------------------+

bool CreateRect(const string name, int x, int y, int w, int h, color clr)
{
   if(ObjectFind(0, name) < 0)
   {
      if(!ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0)) return false;
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE,  false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,      true);
   }
   ObjectSetInteger(0, name, OBJPROP_CORNER,      CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,   x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,   y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,       w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,       h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,     clr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_COLOR,       C_SEP);
   return true;
}

bool CreateLabel(const string name, int x, int y, const string text,
                 color clr, int fs = SEA_FONT_SZ)
{
   if(ObjectFind(0, name) < 0)
   {
      if(!ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0)) return false;
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
   }
   ObjectSetInteger(0, name, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR,    ANCHOR_LEFT_UPPER);
   ObjectSetString (0, name, OBJPROP_TEXT,      text);
   ObjectSetString (0, name, OBJPROP_FONT,      SEA_FONT);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  fs);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clr);
   return true;
}

bool CreateButton(const string name, int x, int y, int w, int h,
                  const string text, color bgClr, color txtClr)
{
   if(ObjectFind(0, name) < 0)
   {
      if(!ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0)) return false;
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN,     true);
   }
   ObjectSetInteger(0, name, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,     w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,     h);
   ObjectSetString (0, name, OBJPROP_TEXT,      text);
   ObjectSetString (0, name, OBJPROP_FONT,      SEA_FONT);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  SEA_FONT_SZ);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,   bgClr);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     txtClr);
   ObjectSetInteger(0, name, OBJPROP_STATE,     false);
   return true;
}

void SetLabelText(const string name, const string text, color clr)
{
   if(ObjectFind(0, name) >= 0)
   {
      ObjectSetString (0, name, OBJPROP_TEXT,  text);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   }
}

void DeleteAllUIObjects()
{
   ObjectsDeleteAll(0, g_prefix);
}

color ScoreColor(double s)
{
   if(s >= 80) return C_GOOD;
   if(s >= 65) return C_MED;
   if(s >= 45) return clrOrange;
   return C_BAD;
}

color ClassColor(const string cls)
{
   if(cls == "A+")   return C_GOOD;
   if(cls == "Good") return C_MED;
   if(cls == "Weak") return clrOrange;
   return C_BAD;
}

color HealthColor(ENUM_HEALTH_STATE hs)
{
   switch(hs)
   {
      case HEALTH_HEALTHY:             return C_GOOD;
      case HEALTH_MILD_CAUTION:        return C'180,220,100';
      case HEALTH_MOMENTUM_WEAKENING:  return C_MED;
      case HEALTH_EXHAUSTION_WATCH:    return clrOrange;
      case HEALTH_EXIT_WATCH:          return C'255,140,0';
      case HEALTH_REVERSAL_CONFIRMED:  return C_BAD;
   }
   return C_TEXT;
}

string ExhaustionBar(double pct)
{
   int fill = (int)MathRound(pct / 10.0);
   string s = "[";
   for(int i = 0; i < 10; i++) s += (i < fill) ? "|" : " ";
   return s + "]";
}

string PeriodStr(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return "M1";  case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15"; case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";  case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";  case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN";
   }
   return "??";
}

string FmtPrice(double p)
{
   return (p == 0) ? "—" : DoubleToString(p, _Digits);
}

//+------------------------------------------------------------------+
//|  SECTION 18 — PANEL BUILD (one-time skeleton creation)           |
//+------------------------------------------------------------------+
void BuildPanel()
{
   int x  = SEA_PANEL_X;
   int y  = SEA_PANEL_Y;
   int w  = SEA_PANEL_W;
   int rh = SEA_ROW_H;

   CreateRect(g_prefix + "BG", x - 5, y - 5, w + 10, 450, InpColorBG);

   CreateRect (g_prefix + "HDR_BG",  x - 5, y - 5, w + 10, rh + 6, InpColorHeader);
   CreateLabel(g_prefix + "HDR_TXT", x + 2,  y,    SEA_VERSION, clrWhite, SEA_FONT_SZ);

   int cy = y + rh + 6;

   CreateLabel(g_prefix + "SYMTF", x, cy, "...", C_DIM, SEA_FONT_SZ_SM);
   cy += rh;

   CreateRect (g_prefix + "SEP1", x - 5, cy, w + 10, 1, C_SEP); cy += 4;
   CreateLabel(g_prefix + "SC_HDR", x, cy, "SETUP SCORE", C_DIM, SEA_FONT_SZ_SM); cy += rh;

   CreateLabel(g_prefix + "SC_BUY_LBL",  x,       cy, "Buy:",  C_BUY,  SEA_FONT_SZ);
   CreateLabel(g_prefix + "SC_BUY_VAL",  x + 36,  cy, "—",     C_TEXT, SEA_FONT_SZ);
   CreateLabel(g_prefix + "SC_BUY_CLS",  x + 78,  cy, "—",     C_DIM,  SEA_FONT_SZ);
   CreateLabel(g_prefix + "SC_BUY_PEN",  x + 128, cy, "",      C_BAD,  SEA_FONT_SZ_SM);
   cy += rh;

   CreateLabel(g_prefix + "SC_SELL_LBL", x,       cy, "Sell:", C_SELL, SEA_FONT_SZ);
   CreateLabel(g_prefix + "SC_SELL_VAL", x + 36,  cy, "—",     C_TEXT, SEA_FONT_SZ);
   CreateLabel(g_prefix + "SC_SELL_CLS", x + 78,  cy, "—",     C_DIM,  SEA_FONT_SZ);
   CreateLabel(g_prefix + "SC_SELL_PEN", x + 128, cy, "",      C_BAD,  SEA_FONT_SZ_SM);
   cy += rh;

   CreateRect (g_prefix + "SEP2", x - 5, cy, w + 10, 1, C_SEP); cy += 4;
   CreateLabel(g_prefix + "COMP_HDR", x, cy, "COMPONENTS  (buy / sell)", C_DIM, SEA_FONT_SZ_SM);
   cy += rh;

   string cLbl[] = {"Trend:", "Structure:", "Location:", "Candle:", "Momentum:", "R:R:"};
   string cKey[] = {"TREND",  "STRUCT",     "LOC",       "CANDLE",  "MOM",       "RR"};
   for(int i = 0; i < 6; i++)
   {
      CreateLabel(g_prefix + "CMP_" + cKey[i] + "_L", x,      cy, cLbl[i], C_DIM,  SEA_FONT_SZ_SM);
      CreateLabel(g_prefix + "CMP_" + cKey[i] + "_V", x + 80, cy, "—/—",   C_TEXT, SEA_FONT_SZ_SM);
      cy += rh - 1;
   }

   CreateRect (g_prefix + "SEP3", x - 5, cy, w + 10, 1, C_SEP); cy += 4;
   CreateLabel(g_prefix + "PEN_HDR",  x, cy, "PENALTIES", C_DIM, SEA_FONT_SZ_SM); cy += rh;
   CreateLabel(g_prefix + "PEN_BUY",  x, cy, "B: none",   C_DIM, SEA_FONT_SZ_SM); cy += rh - 2;
   CreateLabel(g_prefix + "PEN_SELL", x, cy, "S: none",   C_DIM, SEA_FONT_SZ_SM); cy += rh;

   CreateRect (g_prefix + "SEP4", x - 5, cy, w + 10, 1, C_SEP); cy += 4;
   CreateLabel(g_prefix + "ST_HDR",    x,       cy, "STOP / TARGET", C_DIM,  SEA_FONT_SZ_SM); cy += rh;
   CreateLabel(g_prefix + "ST_STOP_L", x,       cy, "Stop:",         C_DIM,  SEA_FONT_SZ_SM);
   CreateLabel(g_prefix + "ST_STOP_V", x + 46,  cy, "—",             C_BAD,  SEA_FONT_SZ_SM);
   CreateLabel(g_prefix + "ST_TGT_L",  x + 130, cy, "Target:",       C_DIM,  SEA_FONT_SZ_SM);
   CreateLabel(g_prefix + "ST_TGT_V",  x + 190, cy, "—",             C_GOOD, SEA_FONT_SZ_SM);
   cy += rh;

   CreateRect (g_prefix + "SEP5", x - 5, cy, w + 10, 1, C_SEP); cy += 4;
   CreateLabel(g_prefix + "TRADE_HDR",   x, cy, "ACTIVE TRADE",    C_DIM,  SEA_FONT_SZ_SM); cy += rh;
   CreateLabel(g_prefix + "TRADE_STATE", x, cy, "No Active Trade", C_DIM,  SEA_FONT_SZ);    cy += rh;
   CreateLabel(g_prefix + "TRADE_ENTRY", x, cy, "",                C_DIM,  SEA_FONT_SZ_SM); cy += rh - 2;
   CreateLabel(g_prefix + "TRADE_BARS",  x, cy, "",                C_DIM,  SEA_FONT_SZ_SM); cy += rh;

   CreateLabel(g_prefix + "EXH_HDR",   x,        cy, "EXHAUSTION",   C_DIM,  SEA_FONT_SZ_SM); cy += rh;
   CreateLabel(g_prefix + "EXH_BAR",   x,        cy, "[          ]", C_DIM,  SEA_FONT_SZ);
   CreateLabel(g_prefix + "EXH_PCT",   x + 130,  cy, "0%",           C_DIM,  SEA_FONT_SZ); cy += rh;
   CreateLabel(g_prefix + "EXH_STATE", x,        cy, "—",            C_DIM,  SEA_FONT_SZ); cy += rh;
   CreateLabel(g_prefix + "EXH_COMP",  x,        cy, "",             C_DIM,  SEA_FONT_SZ_SM); cy += rh + 2;

   CreateRect(g_prefix + "SEP6", x - 5, cy, w + 10, 1, C_SEP); cy += 6;
   int bw = 84, bh = 20, gap = 5;

   CreateButton(g_prefix + "BTN_BUY_EVAL",  x,              cy, bw, bh, "Eval Buy",  C'15,45,105', C_BUY);
   CreateButton(g_prefix + "BTN_SELL_EVAL", x + bw + gap,   cy, bw, bh, "Eval Sell", C'105,15,25', C_SELL);
   cy += bh + gap;

   CreateButton(g_prefix + "BTN_SET_BUY",  x,              cy, bw, bh, "Set Buy",  C'10,35,80',  C_BUY);
   CreateButton(g_prefix + "BTN_SET_SELL", x + bw + gap,   cy, bw, bh, "Set Sell", C'80,10,20',  C_SELL);
   CreateButton(g_prefix + "BTN_CLEAR",    x + 2*(bw+gap), cy, bw, bh, "Clear",    C'45,25,25',  C_TEXT);
}

//+------------------------------------------------------------------+
//|  SECTION 19 — PANEL REFRESH (dynamic value updates each bar/timer)|
//+------------------------------------------------------------------+
void RefreshPanel()
{
   int x = SEA_PANEL_X;

   string sym = _Symbol + "  " + PeriodStr(_Period) +
                "  HTF:" + PeriodStr(InpHTF) +
                "  ATR:" + DoubleToString(g_atr / _Point, 0) + "p";
   SetLabelText(g_prefix + "SYMTF", sym, C_DIM);

   // FIX-R4: Use g_scoreValid flag instead of fragile buyClass != "Avoid" check.
   //         The old logic silently showed "—" for any legitimate "Avoid" score.
   bool ev = g_scoreValid;

   // Buy score row
   SetLabelText(g_prefix + "SC_BUY_VAL",
                ev ? DoubleToString(g_score.buyTotal, 0) : "—",
                ev ? ScoreColor(g_score.buyTotal) : C_DIM);
   SetLabelText(g_prefix + "SC_BUY_CLS",
                ev ? ("[" + g_score.buyClass + "]") : "—",
                ev ? ClassColor(g_score.buyClass) : C_DIM);
   SetLabelText(g_prefix + "SC_BUY_PEN",
                (ev && g_score.buyPenalty < 0) ? DoubleToString(g_score.buyPenalty, 0) : "",
                C_BAD);

   // Sell score row
   SetLabelText(g_prefix + "SC_SELL_VAL",
                ev ? DoubleToString(g_score.sellTotal, 0) : "—",
                ev ? ScoreColor(g_score.sellTotal) : C_DIM);
   SetLabelText(g_prefix + "SC_SELL_CLS",
                ev ? ("[" + g_score.sellClass + "]") : "—",
                ev ? ClassColor(g_score.sellClass) : C_DIM);
   SetLabelText(g_prefix + "SC_SELL_PEN",
                (ev && g_score.sellPenalty < 0) ? DoubleToString(g_score.sellPenalty, 0) : "",
                C_BAD);

   // Component breakdown
   string cKey[] = {"TREND","STRUCT","LOC","CANDLE","MOM","RR"};
   double bv[]   = { g_score.buyComp.trend,  g_score.buyComp.structure, g_score.buyComp.location,
                     g_score.buyComp.candle, g_score.buyComp.momentum,  g_score.buyComp.rr };
   double sv[]   = { g_score.sellComp.trend,  g_score.sellComp.structure, g_score.sellComp.location,
                     g_score.sellComp.candle, g_score.sellComp.momentum,  g_score.sellComp.rr };
   int    wt[]   = { InpWtTrend, InpWtStructure, InpWtLocation, InpWtCandle, InpWtMomentum, InpWtRR };

   for(int i = 0; i < 6; i++)
   {
      string txt = ev ?
         DoubleToString(bv[i], 0) + "/" + IntegerToString(wt[i]) + "  " +
         DoubleToString(sv[i], 0) + "/" + IntegerToString(wt[i]) :
         "—/—";
      SetLabelText(g_prefix + "CMP_" + cKey[i] + "_V", txt, ev ? C_TEXT : C_DIM);
   }

   // Penalty log
   SetLabelText(g_prefix + "PEN_BUY",
                "B: " + (g_score.buyLog  != "" ? g_score.buyLog  : "none"),
                g_score.buyPenalty  < 0 ? C_BAD : C_DIM);
   SetLabelText(g_prefix + "PEN_SELL",
                "S: " + (g_score.sellLog != "" ? g_score.sellLog : "none"),
                g_score.sellPenalty < 0 ? C_BAD : C_DIM);

   // Stop / Target
   SetLabelText(g_prefix + "ST_STOP_V", FmtPrice(g_score.suggestStop),   C_BAD);
   SetLabelText(g_prefix + "ST_TGT_V",  FmtPrice(g_score.suggestTarget), C_GOOD);

   // Active trade section
   if(g_trade.tradeState == TRADE_IDLE)
   {
      SetLabelText(g_prefix + "TRADE_STATE", "No Active Trade", C_DIM);
      SetLabelText(g_prefix + "TRADE_ENTRY", "",               C_DIM);
      SetLabelText(g_prefix + "TRADE_BARS",  "",               C_DIM);
      SetLabelText(g_prefix + "EXH_BAR",     "[          ]",   C_DIM);
      SetLabelText(g_prefix + "EXH_PCT",     "0%",             C_DIM);
      SetLabelText(g_prefix + "EXH_STATE",   "—",              C_DIM);
      SetLabelText(g_prefix + "EXH_COMP",    "",               C_DIM);
   }
   else
   {
      bool    isBuy = (g_trade.tradeState == TRADE_ACTIVE_BUY);
      color   dirC  = isBuy ? C_BUY : C_SELL;
      color   exhC  = HealthColor(g_trade.healthState);

      SetLabelText(g_prefix + "TRADE_STATE",
                   "▶ " + (isBuy ? "LONG" : "SHORT") + " Active", dirC);
      SetLabelText(g_prefix + "TRADE_ENTRY",
                   "Entry: " + FmtPrice(g_trade.entryPrice) +
                   "  ATR0: " + DoubleToString(g_trade.entryATR / _Point, 0) + "p",
                   C_DIM);
      SetLabelText(g_prefix + "TRADE_BARS",
                   "Bars: " + IntegerToString(g_trade.barsHeld) +
                   "  NoExt: " + IntegerToString(g_trade.barsSinceNewExtreme),
                   C_DIM);

      int pct = (int)MathRound(g_trade.exhaustion);
      SetLabelText(g_prefix + "EXH_BAR",   ExhaustionBar(g_trade.exhaustion), exhC);
      SetLabelText(g_prefix + "EXH_PCT",   IntegerToString(pct) + "%",        exhC);
      SetLabelText(g_prefix + "EXH_STATE", g_trade.healthText,                exhC);

      string cLine =
         "Bdy:" + DoubleToString(g_trade.exh_body,       0) +
         " Wk:" + DoubleToString(g_trade.exh_wick,       0) +
         " Dv:" + DoubleToString(g_trade.exh_divergence, 0) +
         " St:" + DoubleToString(g_trade.exh_stall,      0) +
         " AT:" + DoubleToString(g_trade.exh_atr,        0) +
         " Pt:" + DoubleToString(g_trade.exh_pattern,    0) +
         " Sp:" + DoubleToString(g_trade.exh_trendBonus, 0);
      SetLabelText(g_prefix + "EXH_COMP", cLine, C_DIM);
   }
}

//+------------------------------------------------------------------+
//|  END OF SmartEdgeEA.mq5                                          |
//+------------------------------------------------------------------+
