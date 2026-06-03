//+------------------------------------------------------------------+
//|                                          HighEndChannel.mq5      |
//|                             High End Channel — TradeMind          |
//|  Four switchable channel types with trend, position, slope,      |
//|  breakout alerts, and a live dashboard for scalping context.      |
//+------------------------------------------------------------------+
#property copyright "TradeMind"
#property version   "1.00"
#property strict
#property indicator_chart_window
#property indicator_buffers 7
#property indicator_plots   4

// Plot 0: Channel fill (upper + lower share one DRAW_FILLING plot)
#property indicator_label1  "Upper;Lower"
#property indicator_type1   DRAW_FILLING
#property indicator_color1  C'0,20,60',C'0,20,60'

// Plot 1: Midline
#property indicator_label2  "Mid"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrGold
#property indicator_style2  STYLE_DOT
#property indicator_width2  1

// Plot 2: Breakout up arrow
#property indicator_label3  "Break Up"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrLime
#property indicator_width3  2

// Plot 3: Breakout down arrow
#property indicator_label4  "Break Down"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrOrangeRed
#property indicator_width4  2

//+------------------------------------------------------------------+
//| Enums                                                             |
//+------------------------------------------------------------------+
enum ENUM_CHANNEL_TYPE
{
   CHANNEL_ATR        = 0,  // ATR Dynamic
   CHANNEL_SWING      = 1,  // Swing Highs/Lows
   CHANNEL_REGRESSION = 2,  // Linear Regression
   CHANNEL_DONCHIAN   = 3   // Donchian Range
};

//+------------------------------------------------------------------+
//| Inputs                                                            |
//+------------------------------------------------------------------+
input group             "─── Channel ──────────────────────"
input ENUM_CHANNEL_TYPE InpType      = CHANNEL_ATR;   // Channel Type
input int               InpPeriod    = 20;             // Period
input double            InpMult      = 2.0;            // Multiplier (ATR / Regression)
input int               InpSwing     = 5;              // Swing Bars (each side)
input group             "─── Visual ────────────────────────"
input color             InpBullColor = clrDodgerBlue;  // Uptrend Color
input color             InpBearColor = clrTomato;      // Downtrend Color
input color             InpFlatColor = clrSilver;      // Flat/Sideways Color
input bool              InpShowDash  = true;           // Show Dashboard
input group             "─── Alerts ────────────────────────"
input bool              InpAlerts    = true;           // Breakout Alerts

//+------------------------------------------------------------------+
//| Buffers                                                           |
//+------------------------------------------------------------------+
double UpperBuf[];       // plot 0 first buffer
double LowerBuf[];       // plot 0 second buffer
double MidBuf[];         // plot 1
double BreakUpBuf[];     // plot 2
double BreakDownBuf[];   // plot 3
double TrendBuf[];       // internal: 1=bull, -1=bear, 0=flat
double SlopeBuf[];       // internal: % slope over InpPeriod bars

//+------------------------------------------------------------------+
//| Globals                                                           |
//+------------------------------------------------------------------+
int    g_atr       = INVALID_HANDLE;
int    g_lastBreak = 0;   // 1=above, -1=below, 0=inside
string g_pfx       = "HEC_";

//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, UpperBuf,     INDICATOR_DATA);
   SetIndexBuffer(1, LowerBuf,     INDICATOR_DATA);
   SetIndexBuffer(2, MidBuf,       INDICATOR_DATA);
   SetIndexBuffer(3, BreakUpBuf,   INDICATOR_DATA);
   SetIndexBuffer(4, BreakDownBuf, INDICATOR_DATA);
   SetIndexBuffer(5, TrendBuf,     INDICATOR_CALCULATIONS);
   SetIndexBuffer(6, SlopeBuf,     INDICATOR_CALCULATIONS);

   ArraySetAsSeries(UpperBuf,     true);
   ArraySetAsSeries(LowerBuf,     true);
   ArraySetAsSeries(MidBuf,       true);
   ArraySetAsSeries(BreakUpBuf,   true);
   ArraySetAsSeries(BreakDownBuf, true);
   ArraySetAsSeries(TrendBuf,     true);
   ArraySetAsSeries(SlopeBuf,     true);

   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   PlotIndexSetInteger(2, PLOT_ARROW,       233);  // filled up triangle
   PlotIndexSetInteger(3, PLOT_ARROW,       234);  // filled down triangle
   PlotIndexSetInteger(2, PLOT_ARROW_SHIFT, 8);
   PlotIndexSetInteger(3, PLOT_ARROW_SHIFT, -8);

   int drawBegin = InpPeriod * 2 + InpSwing * 2 + 2;
   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, drawBegin);
   PlotIndexSetInteger(1, PLOT_DRAW_BEGIN, drawBegin);

   IndicatorSetString(INDICATOR_SHORTNAME,
      "HEC[" + EnumToString(InpType) + "/" + IntegerToString(InpPeriod) + "]");

   if(InpType == CHANNEL_ATR)
   {
      g_atr = iATR(_Symbol, _Period, InpPeriod);
      if(g_atr == INVALID_HANDLE)
      {
         Print("HEC: ATR handle creation failed");
         return INIT_FAILED;
      }
   }

   if(InpShowDash) CreateDash();

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(g_atr != INVALID_HANDLE) { IndicatorRelease(g_atr); g_atr = INVALID_HANDLE; }
   DeleteDash();
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
   int minBars = InpPeriod + InpSwing * 2 + 2;
   if(rates_total < minBars) return 0;

   ArraySetAsSeries(high,  true);
   ArraySetAsSeries(low,   true);
   ArraySetAsSeries(close, true);

   double atr[];
   if(InpType == CHANNEL_ATR)
   {
      ArraySetAsSeries(atr, true);
      if(CopyBuffer(g_atr, 0, 0, rates_total, atr) <= 0) return prev_calculated;
   }

   int start = (prev_calculated == 0) ? rates_total - minBars - 1 : 1;
   if(start < 0) start = 0;

   for(int i = start; i >= 0; i--)
   {
      double upper = EMPTY_VALUE, lower = EMPTY_VALUE;

      switch(InpType)
      {
         case CHANNEL_ATR:
            CalcATR(i, close, atr, rates_total, upper, lower);
            break;
         case CHANNEL_SWING:
            CalcSwing(i, high, low, rates_total, upper, lower);
            break;
         case CHANNEL_REGRESSION:
            CalcRegression(i, close, rates_total, upper, lower);
            break;
         case CHANNEL_DONCHIAN:
            CalcDonchian(i, high, low, rates_total, upper, lower);
            break;
      }

      UpperBuf[i] = upper;
      LowerBuf[i] = lower;
      MidBuf[i]   = (upper != EMPTY_VALUE && lower != EMPTY_VALUE)
                    ? (upper + lower) * 0.5 : EMPTY_VALUE;

      // Slope: % change of midline over InpPeriod bars
      int ref = i + InpPeriod;
      if(ref < rates_total && MidBuf[ref] != EMPTY_VALUE && MidBuf[ref] != 0.0)
         SlopeBuf[i] = (MidBuf[i] - MidBuf[ref]) / MidBuf[ref] * 100.0;
      else
         SlopeBuf[i] = 0.0;

      if(SlopeBuf[i] >  0.02)     TrendBuf[i] =  1.0;
      else if(SlopeBuf[i] < -0.02) TrendBuf[i] = -1.0;
      else                          TrendBuf[i] =  0.0;

      BreakUpBuf[i]   = EMPTY_VALUE;
      BreakDownBuf[i] = EMPTY_VALUE;
   }

   // Breakout detection on bar 0 only
   if(UpperBuf[0] != EMPTY_VALUE && LowerBuf[0] != EMPTY_VALUE)
   {
      bool above = close[0] > UpperBuf[0];
      bool below = close[0] < LowerBuf[0];

      if(above && g_lastBreak != 1)
      {
         BreakUpBuf[0] = UpperBuf[0];
         if(InpAlerts)
            Alert(_Symbol + " [HEC] ▲ Break ABOVE channel | " +
                  DoubleToString(UpperBuf[0], _Digits));
         g_lastBreak = 1;
      }
      else if(below && g_lastBreak != -1)
      {
         BreakDownBuf[0] = LowerBuf[0];
         if(InpAlerts)
            Alert(_Symbol + " [HEC] ▼ Break BELOW channel | " +
                  DoubleToString(LowerBuf[0], _Digits));
         g_lastBreak = -1;
      }
      else if(!above && !below)
      {
         g_lastBreak = 0;
      }
   }

   ApplyFillColor(TrendBuf[0]);

   if(InpShowDash)
      UpdateDash(close[0], UpperBuf[0], LowerBuf[0], TrendBuf[0], SlopeBuf[0]);

   return rates_total;
}

//+------------------------------------------------------------------+
// ATR Dynamic: SMA ± (multiplier × ATR)
//+------------------------------------------------------------------+
void CalcATR(int i, const double &close[], const double &atr[],
             int total, double &upper, double &lower)
{
   if(i + InpPeriod >= total || atr[i] <= 0.0)
      { upper = EMPTY_VALUE; lower = EMPTY_VALUE; return; }

   double sum = 0;
   for(int j = i; j < i + InpPeriod; j++) sum += close[j];
   double ma = sum / InpPeriod;
   upper = ma + InpMult * atr[i];
   lower = ma - InpMult * atr[i];
}

//+------------------------------------------------------------------+
// Donchian: highest high and lowest low over period
//+------------------------------------------------------------------+
void CalcDonchian(int i, const double &high[], const double &low[],
                  int total, double &upper, double &lower)
{
   if(i + InpPeriod >= total)
      { upper = EMPTY_VALUE; lower = EMPTY_VALUE; return; }

   upper = high[i];
   lower = low[i];
   for(int j = i + 1; j < i + InpPeriod; j++)
   {
      if(high[j] > upper) upper = high[j];
      if(low[j]  < lower) lower = low[j];
   }
}

//+------------------------------------------------------------------+
// Linear Regression: best-fit line ± (multiplier × std-dev)
//+------------------------------------------------------------------+
void CalcRegression(int i, const double &close[], int total,
                    double &upper, double &lower)
{
   int n = InpPeriod;
   if(i + n >= total)
      { upper = EMPTY_VALUE; lower = EMPTY_VALUE; return; }

   // x=0 → oldest bar (i+n-1), x=n-1 → newest bar (i)
   double sumX=0, sumY=0, sumXY=0, sumX2=0;
   for(int j = 0; j < n; j++)
   {
      double x = (double)j;
      double y = close[i + (n - 1 - j)];
      sumX  += x;
      sumY  += y;
      sumXY += x * y;
      sumX2 += x * x;
   }

   double D = n * sumX2 - sumX * sumX;
   if(MathAbs(D) < 1e-10)
      { upper = EMPTY_VALUE; lower = EMPTY_VALUE; return; }

   double b   = (n * sumXY - sumX * sumY) / D;
   double a   = (sumY - b * sumX) / n;
   double reg = a + b * (n - 1);    // value at newest bar

   double var = 0;
   for(int j = 0; j < n; j++)
   {
      double y   = close[i + (n - 1 - j)];
      double fit = a + b * (double)j;
      double res = y - fit;
      var += res * res;
   }
   double sd = MathSqrt(var / n);

   upper = reg + InpMult * sd;
   lower = reg - InpMult * sd;
}

//+------------------------------------------------------------------+
// Swing Channel: projects lines through last 2 swing highs / lows
//+------------------------------------------------------------------+
void CalcSwing(int i, const double &high[], const double &low[],
               int total, double &upper, double &lower)
{
   int maxLook  = MathMin(InpPeriod * 20, total - InpSwing - 1);
   int sh[2]    = {-1, -1};
   int shCount  = 0;
   int sl[2]    = {-1, -1};
   int slCount  = 0;

   for(int j = i + InpSwing; j < i + maxLook; j++)
   {
      if(j + InpSwing >= total) break;
      if(shCount < 2)
      {
         bool ok = true;
         for(int k = 1; k <= InpSwing && ok; k++)
         {
            if(high[j-k] >= high[j]) ok = false;
            if(high[j+k] >= high[j]) ok = false;
         }
         if(ok) sh[shCount++] = j;
      }
      if(slCount < 2)
      {
         bool ok = true;
         for(int k = 1; k <= InpSwing && ok; k++)
         {
            if(low[j-k] <= low[j]) ok = false;
            if(low[j+k] <= low[j]) ok = false;
         }
         if(ok) sl[slCount++] = j;
      }
      if(shCount >= 2 && slCount >= 2) break;
   }

   if(shCount < 1 || slCount < 1)
      { upper = EMPTY_VALUE; lower = EMPTY_VALUE; return; }

   // sh[0] = more recent (smaller index), sh[1] = older (larger index)
   if(shCount >= 2)
   {
      double slope_h = (high[sh[0]] - high[sh[1]]) / (double)(sh[1] - sh[0]);
      upper = high[sh[0]] + slope_h * (double)(sh[0] - i);
   }
   else
   {
      upper = high[sh[0]];
   }

   if(slCount >= 2)
   {
      double slope_l = (low[sl[0]] - low[sl[1]]) / (double)(sl[1] - sl[0]);
      lower = low[sl[0]] + slope_l * (double)(sl[0] - i);
   }
   else
   {
      lower = low[sl[0]];
   }

   if(upper < lower) { double t = upper; upper = lower; lower = t; }
}

//+------------------------------------------------------------------+
// Dim a color to ~25% intensity for use as channel fill
//+------------------------------------------------------------------+
color DimColor(color c)
{
   uint raw = (uint)c;
   uchar r  = (uchar)(raw & 0xFF);
   uchar g  = (uchar)((raw >> 8) & 0xFF);
   uchar b  = (uchar)((raw >> 16) & 0xFF);
   return (color)(((uint)(b / 4) << 16) | ((uint)(g / 4) << 8) | (uint)(r / 4));
}

void ApplyFillColor(double trend)
{
   color base = (trend > 0) ? InpBullColor : (trend < 0 ? InpBearColor : InpFlatColor);
   color dim  = DimColor(base);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 0, dim);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 1, dim);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, 0, base);  // midline at full brightness
}

//+------------------------------------------------------------------+
// Dashboard
//+------------------------------------------------------------------+
void CreateLabel(const string name, int x, int y, int fontSize = 8)
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,    CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_COLOR,     clrSilver);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,  fontSize);
   ObjectSetString(0,  name, OBJPROP_FONT,      "Consolas");
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_BACK,       false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER,     1);
}

void CreateDash()
{
   ObjectCreate(0, g_pfx+"BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, g_pfx+"BG", OBJPROP_CORNER,      CORNER_LEFT_UPPER);
   ObjectSetInteger(0, g_pfx+"BG", OBJPROP_XDISTANCE,   8);
   ObjectSetInteger(0, g_pfx+"BG", OBJPROP_YDISTANCE,   28);
   ObjectSetInteger(0, g_pfx+"BG", OBJPROP_XSIZE,       195);
   ObjectSetInteger(0, g_pfx+"BG", OBJPROP_YSIZE,       118);
   ObjectSetInteger(0, g_pfx+"BG", OBJPROP_BGCOLOR,     C'8,8,18');
   ObjectSetInteger(0, g_pfx+"BG", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, g_pfx+"BG", OBJPROP_COLOR,       C'35,35,75');
   ObjectSetInteger(0, g_pfx+"BG", OBJPROP_SELECTABLE,  false);
   ObjectSetInteger(0, g_pfx+"BG", OBJPROP_BACK,        false);
   ObjectSetInteger(0, g_pfx+"BG", OBJPROP_ZORDER,      0);

   CreateLabel(g_pfx+"TITLE",  16, 35, 9);
   CreateLabel(g_pfx+"TYPE",   16, 53);
   CreateLabel(g_pfx+"TREND",  16, 68);
   CreateLabel(g_pfx+"POS",    16, 83);
   CreateLabel(g_pfx+"SLOPE",  16, 98);
   CreateLabel(g_pfx+"STATUS", 16, 113);

   ObjectSetString(0,  g_pfx+"TITLE", OBJPROP_TEXT,  "  HIGH END CHANNEL");
   ObjectSetInteger(0, g_pfx+"TITLE", OBJPROP_COLOR, clrDodgerBlue);
}

void UpdateDash(double price, double upper, double lower,
                double trend, double slope)
{
   if(upper == EMPTY_VALUE || lower == EMPTY_VALUE) return;

   // Type
   string typeStr = "";
   switch(InpType)
   {
      case CHANNEL_ATR:
         typeStr = "ATR   P=" + IntegerToString(InpPeriod) + "  M=" + DoubleToString(InpMult,1);
         break;
      case CHANNEL_SWING:
         typeStr = "SWING  Bars=" + IntegerToString(InpSwing);
         break;
      case CHANNEL_REGRESSION:
         typeStr = "REG   P=" + IntegerToString(InpPeriod) + "  D=" + DoubleToString(InpMult,1);
         break;
      case CHANNEL_DONCHIAN:
         typeStr = "DOCHI  P=" + IntegerToString(InpPeriod);
         break;
   }
   ObjectSetString(0, g_pfx+"TYPE", OBJPROP_TEXT, typeStr);

   // Trend
   string trendStr = (trend > 0) ? "BULL  ▲" : (trend < 0 ? "BEAR  ▼" : "FLAT  ─");
   color  trendCol = (trend > 0) ? InpBullColor : (trend < 0 ? InpBearColor : InpFlatColor);
   ObjectSetString(0,  g_pfx+"TREND", OBJPROP_TEXT,  "Trend  " + trendStr);
   ObjectSetInteger(0, g_pfx+"TREND", OBJPROP_COLOR, trendCol);

   // Channel position
   double range = upper - lower;
   double pos   = (range > 1e-10) ? (price - lower) / range * 100.0 : 50.0;
   pos = MathMax(0.0, MathMin(100.0, pos));
   string posZone = (pos > 70) ? "HIGH  ↑" : (pos < 30 ? "LOW   ↓" : "MID   ~");
   color  posCol  = (pos > 70) ? clrTomato  : (pos < 30 ? clrLime   : clrGold);
   ObjectSetString(0,  g_pfx+"POS",  OBJPROP_TEXT,  StringFormat("Pos    %.0f%%  %s", pos, posZone));
   ObjectSetInteger(0, g_pfx+"POS",  OBJPROP_COLOR, posCol);

   // Slope
   color slopeCol = (slope >  0.02) ? InpBullColor :
                    (slope < -0.02) ? InpBearColor : InpFlatColor;
   ObjectSetString(0,  g_pfx+"SLOPE", OBJPROP_TEXT,  StringFormat("Slope  %+.4f%%", slope));
   ObjectSetInteger(0, g_pfx+"SLOPE", OBJPROP_COLOR, slopeCol);

   // Status
   bool above = price > upper, below = price < lower;
   string statusStr = above ? "● BREAK UP   ▲" : (below ? "● BREAK DOWN ▼" : "● INSIDE CHANNEL");
   color  statusCol = above ? clrLime : (below ? clrOrangeRed : clrSilver);
   ObjectSetString(0,  g_pfx+"STATUS", OBJPROP_TEXT,  statusStr);
   ObjectSetInteger(0, g_pfx+"STATUS", OBJPROP_COLOR, statusCol);
}

void DeleteDash()
{
   string ids[] = {"BG","TITLE","TYPE","TREND","POS","SLOPE","STATUS"};
   for(int i = 0; i < ArraySize(ids); i++)
      ObjectDelete(0, g_pfx + ids[i]);
   ChartRedraw(0);
}
//+------------------------------------------------------------------+
