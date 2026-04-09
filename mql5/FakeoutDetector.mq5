//+------------------------------------------------------------------+
//|                                              FakeoutDetector.mq5  |
//|                        TradeMind Fakeout Detection Indicator       |
//|  Scores MA50 crosses with fakeout probability (0-10) using        |
//|  6 quantitative factors. Tracks cross lifecycle to confirm.       |
//+------------------------------------------------------------------+
#property copyright "TradeMind"
#property link      ""
#property version   "1.00"
#property strict
#property indicator_chart_window
#property indicator_plots   1
#property indicator_buffers 1
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_width1  2
#property indicator_label1  "MA"

//+------------------------------------------------------------------+
//| Enums                                                              |
//+------------------------------------------------------------------+
enum ENUM_CROSS_STATUS
{
   CROSS_DETECTED = 0,           // Just detected, scoring done
   CROSS_MONITORING,              // Watching for confirmation
   CROSS_CONFIRMED_BREAKOUT,      // Price held — real move
   CROSS_CONFIRMED_FAKEOUT,       // Price re-crossed — trap
};

enum ENUM_CROSS_DIR
{
   CROSS_BULLISH = 0,            // Price crossed above MA
   CROSS_BEARISH,                 // Price crossed below MA
};

enum ENUM_MA_METHOD
{
   MA_SMA = 0,                   // Simple Moving Average
   MA_EMA,                        // Exponential Moving Average
};

//+------------------------------------------------------------------+
//| Structures                                                         |
//+------------------------------------------------------------------+
struct CrossEvent
{
   datetime          time;
   ENUM_CROSS_DIR    direction;
   double            crossPrice;
   double            maPrice;
   int               fakeoutScore;
   string            scoreBreakdown;
   ENUM_CROSS_STATUS status;
   int               monitorBarsLeft;
   bool              alertFired;
   double            wickRatio;
   double            penetrationATR;
   double            maSlope;
   double            rsiValue;
   double            bodyRatio;
   int               recentCrosses;
};

//+------------------------------------------------------------------+
//| Input Parameters                                                   |
//+------------------------------------------------------------------+
input group "=== MA Settings ==="
input int            InpMAPeriod           = 50;      // MA Period
input ENUM_MA_METHOD InpMAMethod           = MA_SMA;  // MA Method

input group "=== Scoring Thresholds ==="
input double   InpSlopeFlatThreshold      = 0.3;     // Slope flatness threshold (x ATR)
input double   InpShallowPenThreshold     = 0.3;     // Shallow penetration threshold (x ATR)
input int      InpRSIOverbought           = 70;      // RSI overbought level
input int      InpRSIOversold             = 30;      // RSI oversold level
input int      InpChoppyThreshold         = 4;       // Crosses above this = choppy
input double   InpWeakBodyThreshold       = 0.3;     // Body/range below this = weak

input group "=== Monitoring ==="
input int      InpMonitorBars             = 10;      // Bars to monitor after cross
input int      InpATRPeriod               = 14;      // ATR period
input int      InpRSIPeriod               = 14;      // RSI period
input int      InpMaxBars                 = 500;     // Max bars to analyze
input int      InpCrossLookback           = 50;      // Lookback for cross frequency
input int      InpSlopeLookback           = 5;       // Bars for MA slope calc

input group "=== Alerts ==="
input bool     InpAlertPopup              = true;    // Alert popup
input bool     InpAlertSound              = true;    // Alert sound
input bool     InpAlertPush               = false;   // Push notification
input bool     InpAlertOnHighRisk         = true;    // Alert on high risk cross (>=7)
input bool     InpAlertOnConfirmedFakeout = true;    // Alert on confirmed fakeout

input group "=== Visual ==="
input bool     InpShowCrossArrows         = true;    // Show cross arrows
input bool     InpShowScoreLabels         = true;    // Show score labels
input bool     InpShowConfirmedMarkers    = true;    // Show confirmed markers
input bool     InpShowDashboard           = true;    // Show dashboard
input int      InpMaxDisplayedCrosses     = 20;      // Max crosses to display

input group "=== Colors ==="
input color    InpMAColor                 = clrDodgerBlue;  // MA line color
input color    InpLowRiskColor            = clrLime;        // Low risk (0-3)
input color    InpMedRiskColor            = clrGold;        // Medium risk (4-6)
input color    InpHighRiskColor           = clrRed;         // High risk (7-10)
input color    InpConfFakeoutColor        = clrMagenta;     // Confirmed fakeout
input color    InpConfBreakoutColor       = clrLime;        // Confirmed breakout

//+------------------------------------------------------------------+
//| Globals                                                            |
//+------------------------------------------------------------------+
string   g_prefix = "FKD_";
double   g_maBuffer[];           // Indicator buffer for MA line
double   g_atr[];                // ATR values (manual calc)
double   g_rsi[];                // RSI values (manual calc)
int      g_lastCalculatedBars = 0;

CrossEvent g_crosses[];
int        g_crossCount = 0;

//--- Running stats
int      g_totalFakeouts       = 0;
int      g_totalBreakouts      = 0;
int      g_totalHighRisk       = 0;
int      g_totalHighRiskCorrect= 0;
double   g_sumFakeoutScore     = 0;
double   g_sumBreakoutScore    = 0;

//+------------------------------------------------------------------+
//| OnInit                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("FakeoutDetector v1.0 initializing...");
   Print("MA(", InpMAPeriod, ") ", (InpMAMethod == MA_SMA ? "SMA" : "EMA"),
         " | ATR(", InpATRPeriod, ") | RSI(", InpRSIPeriod, ")");

   SetIndexBuffer(0, g_maBuffer, INDICATOR_DATA);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, InpMAColor);
   PlotIndexSetString(0, PLOT_LABEL, "MA(" + IntegerToString(InpMAPeriod) + ")");
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);

   CleanAllObjects();
   Comment("");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   CleanAllObjects();
   Comment("");
   Print("FakeoutDetector deinitialized");
}

//+------------------------------------------------------------------+
//| OnCalculate                                                        |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   //--- Not enough data
   if(rates_total < InpMAPeriod + 1) return rates_total;

   //--- New bar guard
   if(rates_total == g_lastCalculatedBars) return rates_total;
   g_lastCalculatedBars = rates_total;

   //--- Set as series (index 0 = current bar)
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(g_maBuffer, true);

   int limit = MathMin(rates_total - 1, InpMaxBars);

   //--- 1. Calculate ATR
   CalculateATR(high, low, close, rates_total, limit);

   //--- 2. Calculate MA
   CalculateMA(close, rates_total, limit);

   //--- 3. Calculate RSI
   CalculateRSI(close, rates_total, limit);

   //--- 4. Detect new crosses
   DetectCrosses(close, high, low, open, time, limit);

   //--- 5. Update cross statuses
   UpdateCrossStatuses(close, time, limit);

   //--- 6. Check alerts
   CheckAlerts();

   //--- 7. Draw everything
   CleanAllObjects();
   if(InpShowCrossArrows)    DrawCrossMarkers(time, high, low);
   if(InpShowScoreLabels)    DrawScoreLabels(time, high, low);
   if(InpShowConfirmedMarkers) DrawConfirmedMarkers(time, high, low);
   if(InpShowDashboard)      BuildDashboard(close, time);

   return rates_total;
}

//+------------------------------------------------------------------+
//| CalculateATR — manual ATR into g_atr[]                            |
//+------------------------------------------------------------------+
void CalculateATR(const double &high[], const double &low[],
                  const double &close[], int totalBars, int limit)
{
   ArrayResize(g_atr, totalBars);
   ArrayInitialize(g_atr, 0);
   ArraySetAsSeries(g_atr, true);

   for(int i = limit - 1; i >= 0; i--)
   {
      if(i + InpATRPeriod >= totalBars) continue;

      double sum = 0;
      for(int j = 0; j < InpATRPeriod; j++)
      {
         int k = i + j;
         double tr1 = high[k] - low[k];
         double tr2 = MathAbs(high[k] - close[k + 1]);
         double tr3 = MathAbs(low[k] - close[k + 1]);
         sum += MathMax(tr1, MathMax(tr2, tr3));
      }
      g_atr[i] = sum / InpATRPeriod;
   }
}

//+------------------------------------------------------------------+
//| CalculateMA — manual SMA or EMA into g_maBuffer[]                 |
//+------------------------------------------------------------------+
void CalculateMA(const double &close[], int totalBars, int limit)
{
   if(InpMAMethod == MA_SMA)
   {
      for(int i = limit - 1; i >= 0; i--)
      {
         if(i + InpMAPeriod >= totalBars) { g_maBuffer[i] = 0; continue; }
         double sum = 0;
         for(int j = 0; j < InpMAPeriod; j++)
            sum += close[i + j];
         g_maBuffer[i] = sum / InpMAPeriod;
      }
   }
   else // EMA
   {
      double multiplier = 2.0 / (InpMAPeriod + 1);
      //--- Seed with SMA
      int seedBar = limit - 1;
      if(seedBar + InpMAPeriod >= totalBars) seedBar = totalBars - InpMAPeriod - 1;
      if(seedBar < 0) return;

      double sum = 0;
      for(int j = 0; j < InpMAPeriod; j++)
         sum += close[seedBar + j];
      g_maBuffer[seedBar] = sum / InpMAPeriod;

      //--- EMA forward (from old to new in series terms)
      for(int i = seedBar - 1; i >= 0; i--)
         g_maBuffer[i] = close[i] * multiplier + g_maBuffer[i + 1] * (1.0 - multiplier);
   }
}

//+------------------------------------------------------------------+
//| CalculateRSI — manual RSI into g_rsi[]                            |
//+------------------------------------------------------------------+
void CalculateRSI(const double &close[], int totalBars, int limit)
{
   ArrayResize(g_rsi, totalBars);
   ArrayInitialize(g_rsi, 50.0); // Default neutral
   ArraySetAsSeries(g_rsi, true);

   if(totalBars < InpRSIPeriod + 2) return;

   //--- Calculate from oldest to newest (series: high index = oldest)
   int startBar = MathMin(limit - 1, totalBars - InpRSIPeriod - 2);
   if(startBar < 0) return;

   //--- Seed: average gain/loss over first RSI period
   double avgGain = 0, avgLoss = 0;
   for(int j = 0; j < InpRSIPeriod; j++)
   {
      int k = startBar + j;
      double change = close[k] - close[k + 1];
      if(change > 0) avgGain += change;
      else           avgLoss -= change;
   }
   avgGain /= InpRSIPeriod;
   avgLoss /= InpRSIPeriod;

   if(avgLoss == 0)
      g_rsi[startBar] = 100.0;
   else
      g_rsi[startBar] = 100.0 - 100.0 / (1.0 + avgGain / avgLoss);

   //--- Smooth forward
   for(int i = startBar - 1; i >= 0; i--)
   {
      double change = close[i] - close[i + 1];
      double gain = (change > 0) ? change : 0;
      double loss = (change < 0) ? -change : 0;
      avgGain = (avgGain * (InpRSIPeriod - 1) + gain) / InpRSIPeriod;
      avgLoss = (avgLoss * (InpRSIPeriod - 1) + loss) / InpRSIPeriod;

      if(avgLoss == 0)
         g_rsi[i] = 100.0;
      else
         g_rsi[i] = 100.0 - 100.0 / (1.0 + avgGain / avgLoss);
   }
}

//+------------------------------------------------------------------+
//| GetMASlope — normalized slope over N bars                          |
//+------------------------------------------------------------------+
double GetMASlope(int bar)
{
   int endBar = bar + InpSlopeLookback;
   if(g_maBuffer[bar] == 0 || g_maBuffer[endBar] == 0 || g_atr[bar] == 0)
      return 0;
   return (g_maBuffer[bar] - g_maBuffer[endBar]) / (InpSlopeLookback * g_atr[bar]);
}

//+------------------------------------------------------------------+
//| DetectCrosses — find new MA cross events                           |
//+------------------------------------------------------------------+
void DetectCrosses(const double &close[], const double &high[],
                   const double &low[], const double &open[],
                   const datetime &time[], int limit)
{
   //--- Only check bar 1 (just closed) against bar 2
   int i = 1;
   if(i + 1 >= limit) return;
   if(g_maBuffer[i] == 0 || g_maBuffer[i + 1] == 0) return;
   if(g_atr[i] == 0) return;

   bool prevAbove = close[i + 1] > g_maBuffer[i + 1];
   bool currAbove = close[i] > g_maBuffer[i];

   if(prevAbove == currAbove) return; // No cross

   //--- Dedup: check if we already have a cross at this time
   for(int j = 0; j < g_crossCount; j++)
      if(g_crosses[j].time == time[i]) return;

   //--- New cross detected
   ENUM_CROSS_DIR dir = currAbove ? CROSS_BULLISH : CROSS_BEARISH;

   CrossEvent evt;
   evt.time            = time[i];
   evt.direction       = dir;
   evt.crossPrice      = close[i];
   evt.maPrice         = g_maBuffer[i];
   evt.status          = CROSS_MONITORING;
   evt.monitorBarsLeft = InpMonitorBars;
   evt.alertFired      = false;

   //--- Score the cross
   ScoreCross(evt, close, high, low, open, i);

   //--- Add to array
   g_crossCount++;
   ArrayResize(g_crosses, g_crossCount);
   g_crosses[g_crossCount - 1] = evt;

   //--- Trim old crosses
   if(g_crossCount > InpMaxDisplayedCrosses * 2)
   {
      int keep = InpMaxDisplayedCrosses;
      for(int k = 0; k < keep; k++)
         g_crosses[k] = g_crosses[g_crossCount - keep + k];
      g_crossCount = keep;
      ArrayResize(g_crosses, g_crossCount);
   }
}

//+------------------------------------------------------------------+
//| ScoreCross — calculate 6-factor fakeout probability                |
//+------------------------------------------------------------------+
void ScoreCross(CrossEvent &evt, const double &close[],
                const double &high[], const double &low[],
                const double &open[], int bar)
{
   int score = 0;
   string breakdown = "";

   //--- Factor 1: MA Slope Flatness (max +2)
   int s1 = ScoreSlopeFlatness(bar);
   score += s1;
   breakdown += "Slope:" + IntegerToString(s1);

   //--- Factor 2: Wick Rejection (max +2)
   int s2 = ScoreWickRejection(evt.direction, high[bar], low[bar],
                                open[bar], close[bar], evt.maPrice);
   score += s2;
   breakdown += " Wick:" + IntegerToString(s2);

   //--- Factor 3: Penetration Depth (max +2)
   int s3 = ScorePenetrationDepth(close[bar], evt.maPrice, bar);
   score += s3;
   breakdown += " Depth:" + IntegerToString(s3);

   //--- Factor 4: RSI Extreme (max +2)
   int s4 = ScoreRSIExtreme(evt.direction, bar);
   score += s4;
   breakdown += " RSI:" + IntegerToString(s4);

   //--- Factor 5: Cross Frequency (max +1)
   int s5 = ScoreCrossFrequency(bar);
   score += s5;
   breakdown += " Freq:" + IntegerToString(s5);

   //--- Factor 6: Body Weakness (max +1)
   int s6 = ScoreBodyWeakness(high[bar], low[bar], open[bar], close[bar]);
   score += s6;
   breakdown += " Body:" + IntegerToString(s6);

   evt.fakeoutScore   = score;
   evt.scoreBreakdown = breakdown;
   evt.maSlope        = GetMASlope(bar);
   evt.rsiValue       = g_rsi[bar];
   evt.recentCrosses  = CountRecentCrosses(bar);

   //--- Store raw factor values
   double range = high[bar] - low[bar];
   if(range > 0)
   {
      double wickThrough = 0;
      if(evt.direction == CROSS_BULLISH && low[bar] < evt.maPrice)
         wickThrough = evt.maPrice - low[bar];
      else if(evt.direction == CROSS_BEARISH && high[bar] > evt.maPrice)
         wickThrough = high[bar] - evt.maPrice;
      evt.wickRatio = wickThrough / range;
      evt.bodyRatio = MathAbs(close[bar] - open[bar]) / range;
   }
   else { evt.wickRatio = 0; evt.bodyRatio = 0; }
   evt.penetrationATR = (g_atr[bar] > 0) ? MathAbs(close[bar] - evt.maPrice) / g_atr[bar] : 0;

   //--- Track high-risk count
   if(score >= 7) g_totalHighRisk++;
}

//+------------------------------------------------------------------+
//| Factor 1: MA Slope Flatness (max +2)                               |
//+------------------------------------------------------------------+
int ScoreSlopeFlatness(int bar)
{
   double slope = MathAbs(GetMASlope(bar));
   if(slope < InpSlopeFlatThreshold * 0.5) return 2; // Very flat
   if(slope < InpSlopeFlatThreshold)        return 1; // Somewhat flat
   return 0; // Trending
}

//+------------------------------------------------------------------+
//| Factor 2: Wick Rejection (max +2)                                  |
//+------------------------------------------------------------------+
int ScoreWickRejection(ENUM_CROSS_DIR dir, double high, double low,
                       double open, double close, double ma)
{
   double range = high - low;
   if(range == 0) return 0;

   double wickThrough = 0;
   if(dir == CROSS_BULLISH)
   {
      //--- Bullish cross: wick below MA = rejection of downside
      if(low < ma)
         wickThrough = ma - low;
   }
   else
   {
      //--- Bearish cross: wick above MA = rejection of upside
      if(high > ma)
         wickThrough = high - ma;
   }

   double ratio = wickThrough / range;
   if(ratio > 0.5) return 2; // Strong wick rejection
   if(ratio > 0.25) return 1;
   return 0;
}

//+------------------------------------------------------------------+
//| Factor 3: Penetration Depth (max +2)                               |
//+------------------------------------------------------------------+
int ScorePenetrationDepth(double close, double ma, int bar)
{
   if(g_atr[bar] == 0) return 0;
   double pen = MathAbs(close - ma) / g_atr[bar];

   if(pen < InpShallowPenThreshold * 0.5) return 2; // Very shallow
   if(pen < InpShallowPenThreshold)        return 1; // Shallow
   return 0; // Deep penetration — likely real
}

//+------------------------------------------------------------------+
//| Factor 4: RSI Extreme (max +2)                                     |
//+------------------------------------------------------------------+
int ScoreRSIExtreme(ENUM_CROSS_DIR dir, int bar)
{
   double rsi = g_rsi[bar];

   if(dir == CROSS_BULLISH)
   {
      //--- Bullish cross while RSI overbought = overextended = fakeout risk
      if(rsi > InpRSIOverbought + 10) return 2;
      if(rsi > InpRSIOverbought)      return 1;
   }
   else
   {
      //--- Bearish cross while RSI oversold = overextended = fakeout risk
      if(rsi < InpRSIOversold - 10) return 2;
      if(rsi < InpRSIOversold)      return 1;
   }
   return 0;
}

//+------------------------------------------------------------------+
//| Factor 5: Cross Frequency (max +1)                                 |
//+------------------------------------------------------------------+
int ScoreCrossFrequency(int bar)
{
   int count = CountRecentCrosses(bar);
   if(count >= InpChoppyThreshold) return 1;
   return 0;
}

//+------------------------------------------------------------------+
//| Factor 6: Body Weakness (max +1)                                   |
//+------------------------------------------------------------------+
int ScoreBodyWeakness(double high, double low, double open, double close)
{
   double range = high - low;
   if(range == 0) return 1;
   double body = MathAbs(close - open);
   double ratio = body / range;

   if(ratio < InpWeakBodyThreshold) return 1;
   return 0;
}

//+------------------------------------------------------------------+
//| CountRecentCrosses — crosses in lookback window                    |
//+------------------------------------------------------------------+
int CountRecentCrosses(int bar)
{
   //--- Count crosses that are still within the lookback window
   //--- Since g_crosses stores recent crosses, just count them
   return g_crossCount;
}

//+------------------------------------------------------------------+
//| UpdateCrossStatuses — lifecycle state machine                      |
//+------------------------------------------------------------------+
void UpdateCrossStatuses(const double &close[], const datetime &time[], int limit)
{
   for(int i = 0; i < g_crossCount; i++)
   {
      if(g_crosses[i].status != CROSS_MONITORING) continue;

      //--- Decrement monitor countdown
      g_crosses[i].monitorBarsLeft--;

      //--- Check if price re-crossed MA (fakeout confirmed)
      double currentClose = close[1]; // Last closed bar
      double currentMA    = g_maBuffer[1];
      if(currentMA == 0) continue;

      bool priceAboveMA = currentClose > currentMA;
      bool wasBullish   = (g_crosses[i].direction == CROSS_BULLISH);

      if((wasBullish && !priceAboveMA) || (!wasBullish && priceAboveMA))
      {
         //--- Price re-crossed → FAKEOUT confirmed
         g_crosses[i].status = CROSS_CONFIRMED_FAKEOUT;
         g_totalFakeouts++;
         g_sumFakeoutScore += g_crosses[i].fakeoutScore;
         if(g_crosses[i].fakeoutScore >= 7) g_totalHighRiskCorrect++;
         continue;
      }

      //--- Monitor period expired — BREAKOUT confirmed
      if(g_crosses[i].monitorBarsLeft <= 0)
      {
         g_crosses[i].status = CROSS_CONFIRMED_BREAKOUT;
         g_totalBreakouts++;
         g_sumBreakoutScore += g_crosses[i].fakeoutScore;
      }
   }
}

//+------------------------------------------------------------------+
//| FireAlert — send alert via configured channels                     |
//+------------------------------------------------------------------+
void FireAlert(string message)
{
   if(InpAlertPopup) Alert(message);
   if(InpAlertSound) PlaySound("alert.wav");
   if(InpAlertPush)  SendNotification(message);
}

//+------------------------------------------------------------------+
//| CheckAlerts — fire alerts for high-risk and confirmed fakeouts     |
//+------------------------------------------------------------------+
void CheckAlerts()
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   for(int i = 0; i < g_crossCount; i++)
   {
      if(g_crosses[i].alertFired) continue;

      //--- High risk alert on detection
      if(InpAlertOnHighRisk && g_crosses[i].fakeoutScore >= 7
         && g_crosses[i].status == CROSS_MONITORING
         && g_crosses[i].monitorBarsLeft >= InpMonitorBars - 1)
      {
         string dir = (g_crosses[i].direction == CROSS_BULLISH) ? "BULL" : "BEAR";
         FireAlert("FakeoutDetector: HIGH RISK " + dir + " cross on " + _Symbol +
                  " | Score: " + IntegerToString(g_crosses[i].fakeoutScore) + "/10" +
                  " | Price: " + DoubleToString(g_crosses[i].crossPrice, digits));
         g_crosses[i].alertFired = true;
      }

      //--- Confirmed fakeout alert
      if(InpAlertOnConfirmedFakeout && g_crosses[i].status == CROSS_CONFIRMED_FAKEOUT)
      {
         string dir = (g_crosses[i].direction == CROSS_BULLISH) ? "BULL" : "BEAR";
         FireAlert("FakeoutDetector: CONFIRMED FAKEOUT " + dir + " on " + _Symbol +
                  " | Score was: " + IntegerToString(g_crosses[i].fakeoutScore) + "/10");
         g_crosses[i].alertFired = true;
      }
   }
}

//+------------------------------------------------------------------+
//| CleanAllObjects — remove FKD_ prefixed objects                     |
//+------------------------------------------------------------------+
void CleanAllObjects()
{
   int total = ObjectsTotal(0);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, g_prefix) == 0)
         ObjectDelete(0, name);
   }
}

//+------------------------------------------------------------------+
//| GetRiskColor — color based on fakeout score                        |
//+------------------------------------------------------------------+
color GetRiskColor(int score)
{
   if(score >= 7) return InpHighRiskColor;
   if(score >= 4) return InpMedRiskColor;
   return InpLowRiskColor;
}

//+------------------------------------------------------------------+
//| GetRiskLabel — text label from score                                |
//+------------------------------------------------------------------+
string GetRiskLabel(int score)
{
   if(score >= 7) return "HIGH";
   if(score >= 4) return "MED";
   return "LOW";
}

//+------------------------------------------------------------------+
//| DrawCrossMarkers — arrows at cross points                          |
//+------------------------------------------------------------------+
void DrawCrossMarkers(const datetime &time[], const double &high[],
                      const double &low[])
{
   int displayed = 0;
   for(int i = g_crossCount - 1; i >= 0 && displayed < InpMaxDisplayedCrosses; i--)
   {
      CrossEvent evt = g_crosses[i];
      string name = g_prefix + "ARR_" + IntegerToString((long)evt.time);

      //--- Find bar index for this cross
      double yPrice;
      int arrowCode;
      if(evt.direction == CROSS_BULLISH)
      {
         yPrice = FindLowAtTime(low, time, evt.time) ;
         arrowCode = 233; // Up arrow
      }
      else
      {
         yPrice = FindHighAtTime(high, time, evt.time);
         arrowCode = 234; // Down arrow
      }

      if(yPrice == 0) continue;

      //--- Offset arrow away from candle
      double offset = (evt.direction == CROSS_BULLISH) ? -g_atr[1] * 0.3 : g_atr[1] * 0.3;
      yPrice += offset;

      color clr = GetRiskColor(evt.fakeoutScore);

      if(!ObjectCreate(0, name, OBJ_ARROW, 0, evt.time, yPrice))
         ObjectMove(0, name, 0, evt.time, yPrice);

      ObjectSetInteger(0, name, OBJPROP_ARROWCODE, arrowCode);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);

      displayed++;
   }
}

//+------------------------------------------------------------------+
//| DrawScoreLabels — "F:7" next to arrows                             |
//+------------------------------------------------------------------+
void DrawScoreLabels(const datetime &time[], const double &high[],
                     const double &low[])
{
   int displayed = 0;
   for(int i = g_crossCount - 1; i >= 0 && displayed < InpMaxDisplayedCrosses; i--)
   {
      CrossEvent evt = g_crosses[i];
      string name = g_prefix + "SCR_" + IntegerToString((long)evt.time);

      double yPrice;
      if(evt.direction == CROSS_BULLISH)
         yPrice = FindLowAtTime(low, time, evt.time) - g_atr[1] * 0.6;
      else
         yPrice = FindHighAtTime(high, time, evt.time) + g_atr[1] * 0.6;

      if(yPrice == 0) continue;

      string text = "F:" + IntegerToString(evt.fakeoutScore);
      color clr = GetRiskColor(evt.fakeoutScore);

      if(!ObjectCreate(0, name, OBJ_TEXT, 0, evt.time, yPrice))
         ObjectMove(0, name, 0, evt.time, yPrice);

      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR,
                       evt.direction == CROSS_BULLISH ? ANCHOR_UPPER : ANCHOR_LOWER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);

      displayed++;
   }
}

//+------------------------------------------------------------------+
//| DrawConfirmedMarkers — checkmark/X after confirmation              |
//+------------------------------------------------------------------+
void DrawConfirmedMarkers(const datetime &time[], const double &high[],
                          const double &low[])
{
   for(int i = 0; i < g_crossCount; i++)
   {
      CrossEvent evt = g_crosses[i];
      if(evt.status != CROSS_CONFIRMED_FAKEOUT && evt.status != CROSS_CONFIRMED_BREAKOUT)
         continue;

      string name = g_prefix + "CNF_" + IntegerToString((long)evt.time);

      double yPrice;
      int arrowCode;
      color clr;

      if(evt.status == CROSS_CONFIRMED_FAKEOUT)
      {
         arrowCode = 251; // X mark
         clr = InpConfFakeoutColor;
      }
      else
      {
         arrowCode = 252; // Checkmark
         clr = InpConfBreakoutColor;
      }

      if(evt.direction == CROSS_BULLISH)
         yPrice = FindLowAtTime(low, time, evt.time) - g_atr[1] * 0.9;
      else
         yPrice = FindHighAtTime(high, time, evt.time) + g_atr[1] * 0.9;

      if(yPrice == 0) continue;

      if(!ObjectCreate(0, name, OBJ_ARROW, 0, evt.time, yPrice))
         ObjectMove(0, name, 0, evt.time, yPrice);

      ObjectSetInteger(0, name, OBJPROP_ARROWCODE, arrowCode);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   }
}

//+------------------------------------------------------------------+
//| FindHighAtTime — get high price at a specific datetime             |
//+------------------------------------------------------------------+
double FindHighAtTime(const double &high[], const datetime &time[], datetime t)
{
   for(int i = 0; i < ArraySize(time); i++)
      if(time[i] == t) return high[i];
   return 0;
}

//+------------------------------------------------------------------+
//| FindLowAtTime — get low price at a specific datetime               |
//+------------------------------------------------------------------+
double FindLowAtTime(const double &low[], const datetime &time[], datetime t)
{
   for(int i = 0; i < ArraySize(time); i++)
      if(time[i] == t) return low[i];
   return 0;
}

//+------------------------------------------------------------------+
//| GetTimeframeString — short TF label                                |
//+------------------------------------------------------------------+
string GetTimeframeString()
{
   switch(Period())
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN";
      default:         return "??";
   }
}

//+------------------------------------------------------------------+
//| BuildDashboard — Comment() with stats                              |
//+------------------------------------------------------------------+
void BuildDashboard(const double &close[], const datetime &time[])
{
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   string dash = "";
   string sep = "========================================\n";

   dash += sep;
   dash += " FakeoutDetector v1.0 | " + _Symbol + " " + GetTimeframeString() + "\n";
   dash += sep;

   //--- Indicators line
   string maLabel = (InpMAMethod == MA_SMA) ? "SMA" : "EMA";
   dash += " " + maLabel + "(" + IntegerToString(InpMAPeriod) + "): "
         + DoubleToString(g_maBuffer[1], digits);

   if(ArraySize(g_atr) > 1 && g_atr[1] > 0)
      dash += " | ATR(" + IntegerToString(InpATRPeriod) + "): "
            + DoubleToString(g_atr[1], digits);

   if(ArraySize(g_rsi) > 1)
      dash += " | RSI(" + IntegerToString(InpRSIPeriod) + "): "
            + DoubleToString(g_rsi[1], 1);

   dash += "\n\n";

   //--- Last cross detail
   if(g_crossCount > 0)
   {
      CrossEvent last = g_crosses[g_crossCount - 1];
      string dir = (last.direction == CROSS_BULLISH) ? "BULLISH ^" : "BEARISH v";
      string risk = GetRiskLabel(last.fakeoutScore);
      string stat = "";
      switch(last.status)
      {
         case CROSS_MONITORING:          stat = "MONITORING (" + IntegerToString(last.monitorBarsLeft) + " bars left)"; break;
         case CROSS_CONFIRMED_BREAKOUT:  stat = "CONFIRMED BREAKOUT"; break;
         case CROSS_CONFIRMED_FAKEOUT:   stat = "CONFIRMED FAKEOUT"; break;
         default:                        stat = "DETECTED"; break;
      }

      dash += " Last Cross: " + dir + " @ " + DoubleToString(last.crossPrice, digits)
            + " | Score: " + IntegerToString(last.fakeoutScore) + "/10 " + risk + "\n";
      dash += "   " + last.scoreBreakdown + "\n";
      dash += "   Status: " + stat + "\n\n";
   }
   else
   {
      dash += " No crosses detected yet.\n\n";
   }

   //--- Stats
   int total = g_totalFakeouts + g_totalBreakouts;
   dash += " Stats:\n";
   dash += "   Crosses: " + IntegerToString(g_crossCount)
         + " | Fakeouts: " + IntegerToString(g_totalFakeouts);

   if(total > 0)
      dash += " (" + IntegerToString((int)MathRound(g_totalFakeouts * 100.0 / total)) + "%)";

   dash += " | Breakouts: " + IntegerToString(g_totalBreakouts) + "\n";

   //--- Average scores
   if(g_totalFakeouts > 0)
      dash += "   Avg Fakeout Score: " + DoubleToString(g_sumFakeoutScore / g_totalFakeouts, 1);
   if(g_totalBreakouts > 0)
      dash += " | Avg Breakout Score: " + DoubleToString(g_sumBreakoutScore / g_totalBreakouts, 1);
   if(g_totalFakeouts > 0 || g_totalBreakouts > 0)
      dash += "\n";

   //--- High risk accuracy
   if(g_totalHighRisk > 0)
      dash += "   High Risk Accuracy: " + IntegerToString(g_totalHighRiskCorrect) + "/"
            + IntegerToString(g_totalHighRisk) + " ("
            + IntegerToString((int)MathRound(g_totalHighRiskCorrect * 100.0 / g_totalHighRisk))
            + "%)\n";

   dash += sep;
   Comment(dash);
}
