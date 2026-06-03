//+------------------------------------------------------------------+
//|                                      SmartTrendlineMapper.mq5    |
//|        TradeMind — S/R Inside User-Drawn Equidistant Channel     |
//|  Draw a channel on the chart (Insert → Channels → Equidistant). |
//|  This indicator reads it and draws S/R zones INSIDE IT ONLY:    |
//|    Ascending channel  →  support zones  (swing lows inside)     |
//|    Descending channel →  resistance zones  (swing highs inside) |
//|  Also draws midline and optional 25%/75% internal guide lines.  |
//+------------------------------------------------------------------+
#property copyright "TradeMind"
#property version   "3.00"
#property strict
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

//+------------------------------------------------------------------+
//| Inputs                                                            |
//+------------------------------------------------------------------+
input group "─── Channel ──────────────────────────────────"
input string InpChanName     = "";      // Channel object name (blank = auto)

input group "─── Zone Detection ───────────────────────────"
input int    InpLookback     = 200;     // Lookback bars
input int    InpPivotStr     = 3;       // Pivot strength (bars each side)
input double InpAtrTol       = 0.6;    // ATR tolerance for zone clustering
input int    InpMinTouches   = 2;       // Min touches per zone
input int    InpMaxZones     = 8;       // Max zones to display

input group "─── Visuals ──────────────────────────────────"
input bool   InpShowInternal = true;    // Show 25% / 75% internal guide lines
input bool   InpShowDash     = true;    // Show dashboard
input color  InpSuptCol      = C'0,90,180';    // Support zone color
input color  InpResCol       = C'180,50,0';    // Resistance zone color

input group "─── Alerts ───────────────────────────────────"
input bool   InpAlerts       = true;    // Alert when price touches zone
input double InpAlertAtr     = 0.3;    // Alert ATR distance

//+------------------------------------------------------------------+
//| Structures                                                        |
//+------------------------------------------------------------------+
struct SZone
{
   double  price;      // zone centrePrice
   double  top;
   double  bot;
   bool    isResist;
   int     touches;
   int     firstBar;   // oldest bar index (series) where zone was seen
   double  score;
   bool    valid;
};

struct SLevel
{
   string name;
   double frac;
   bool   always;
};

//+------------------------------------------------------------------+
//| Globals                                                           |
//+------------------------------------------------------------------+
int    g_atr    = INVALID_HANDLE;
string g_pfx    = "STM_";
SZone  g_zones[20];
int    g_nZones = 0;

// Channel state — populated by ReadChannel()
bool     g_chanOk    = false;
double   g_chanUpperA = 0;   // upper line intercept: price at g_chanT1
double   g_chanSlope  = 0;   // price per second (chronological)
datetime g_chanT1     = 0;   // reference datetime
double   g_chanWidth  = 0;   // constant vertical gap between upper/lower (positive)
bool     g_ascending  = false;

//+------------------------------------------------------------------+
int OnInit()
{
   IndicatorSetString(INDICATOR_SHORTNAME, "STM-SR");
   g_atr = iATR(_Symbol, _Period, 14);
   if(g_atr == INVALID_HANDLE) { Print("STM: ATR failed"); return INIT_FAILED; }
   if(InpShowDash) CreateDash();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_atr != INVALID_HANDLE) { IndicatorRelease(g_atr); g_atr = INVALID_HANDLE; }
   DeleteAllObjects();
}

//+------------------------------------------------------------------+
// Channel boundary helpers
// upper(T) = g_chanUpperA + g_chanSlope * (T - g_chanT1)
// lower(T) = upper(T) - g_chanWidth
//+------------------------------------------------------------------+
double UpperAt(datetime t)
{
   return g_chanUpperA + g_chanSlope * (double)(t - g_chanT1);
}
double LowerAt(datetime t) { return UpperAt(t) - g_chanWidth; }

//+------------------------------------------------------------------+
// Read the first OBJ_CHANNEL from the chart.
// Returns true if a valid channel was found and parsed.
//+------------------------------------------------------------------+
bool ReadChannel()
{
   int n = ObjectsTotal(0, 0, -1);
   for(int i = 0; i < n; i++)
   {
      string nm = ObjectName(0, i, 0, -1);
      if(StringFind(nm, g_pfx) == 0) continue;
      if((int)ObjectGetInteger(0, nm, OBJPROP_TYPE) != OBJ_CHANNEL) continue;
      if(InpChanName != "" && nm != InpChanName) continue;

      datetime t1 = (datetime)ObjectGetInteger(0, nm, OBJPROP_TIME,  0);
      double   p1 = ObjectGetDouble(0, nm,            OBJPROP_PRICE, 0);
      datetime t2 = (datetime)ObjectGetInteger(0, nm, OBJPROP_TIME,  1);
      double   p2 = ObjectGetDouble(0, nm,            OBJPROP_PRICE, 1);
      datetime t3 = (datetime)ObjectGetInteger(0, nm, OBJPROP_TIME,  2);
      double   p3 = ObjectGetDouble(0, nm,            OBJPROP_PRICE, 2);

      if(t1 == t2) continue;

      double slope     = (p2 - p1) / (double)(t2 - t1);  // price per second
      double mainAtT3  = p1 + slope * (double)(t3 - t1);  // main line at t3
      double w         = mainAtT3 - p3;                   // signed: +ve = main is upper

      // Ensure g_chanUpperA is always the UPPER line's intercept at t1
      double upperA = (w >= 0.0) ? p1 : (p1 - w);        // p1 + |w| if main is lower

      g_chanT1      = t1;
      g_chanSlope   = slope;
      g_chanUpperA  = upperA;
      g_chanWidth   = MathAbs(w);
      g_ascending   = (slope > 0.0);

      return (g_chanWidth > 1e-10);
   }
   return false;
}

//+------------------------------------------------------------------+
// Detect S/R zones from swing points inside the channel.
// Ascending  → look for swing LOWS  → support zones
// Descending → look for swing HIGHS → resistance zones
//+------------------------------------------------------------------+
void DetectZones(const double &high[], const double &low[],
                 const double &atr[], const datetime &time[], int total)
{
   g_nZones = 0;
   double tol   = atr[0] * InpAtrTol;
   int    limit = MathMin(InpLookback, total - InpPivotStr - 1);
   int    s     = InpPivotStr;

   // Channel position at bar 0 — used to filter out stale zones
   double upNow = UpperAt(time[0]);
   double loNow = LowerAt(time[0]);

   for(int i = s; i < limit; i++)
   {
      double upI = UpperAt(time[i]);
      double loI = LowerAt(time[i]);

      // Rough channel containment check (with 1 ATR margin)
      if(high[i] < loI - tol || low[i] > upI + tol) continue;

      bool isSwH = true, isSwL = true;
      for(int k = 1; k <= s; k++)
      {
         if(high[i-k] >= high[i] || high[i+k] >= high[i]) isSwH = false;
         if(low[i-k]  <= low[i]  || low[i+k]  <= low[i])  isSwL = false;
      }

      double swPx    = 0;
      bool   isResist = false;

      if(g_ascending && isSwL)
      {
         swPx     = low[i];
         isResist = false;
      }
      else if(!g_ascending && isSwH)
      {
         swPx     = high[i];
         isResist = true;
      }
      else continue;

      // Only include swings whose price is still inside the channel at bar 0
      if(swPx < loNow - tol || swPx > upNow + tol) continue;

      // Find existing cluster or create new zone
      int found = -1;
      for(int z = 0; z < g_nZones; z++)
      {
         if(g_zones[z].isResist != isResist) continue;
         if(MathAbs(g_zones[z].price - swPx) <= tol) { found = z; break; }
      }

      if(found >= 0)
      {
         // Running-average centre
         g_zones[found].price = (g_zones[found].price * g_zones[found].touches + swPx)
                                / (g_zones[found].touches + 1);
         g_zones[found].top   = g_zones[found].price + tol * 0.45;
         g_zones[found].bot   = g_zones[found].price - tol * 0.45;
         g_zones[found].touches++;
         if(i > g_zones[found].firstBar) g_zones[found].firstBar = i;
      }
      else if(g_nZones < 19)
      {
         g_zones[g_nZones].price    = swPx;
         g_zones[g_nZones].top      = swPx + tol * 0.45;
         g_zones[g_nZones].bot      = swPx - tol * 0.45;
         g_zones[g_nZones].isResist = isResist;
         g_zones[g_nZones].touches  = 1;
         g_zones[g_nZones].firstBar = i;
         g_zones[g_nZones].valid    = true;
         g_zones[g_nZones].score    = 0;
         g_nZones++;
      }
   }
}

//+------------------------------------------------------------------+
// Draw internal diagonal guide lines (25%, midline at 50%, 75%)
//+------------------------------------------------------------------+
void DrawInternalLines(const datetime &time[], int total)
{
   int leftBar = MathMin(InpLookback - 1, total - 1);

   SLevel levels[3];
   levels[0].name = "Q1";  levels[0].frac = 0.25; levels[0].always = false;
   levels[1].name = "MID"; levels[1].frac = 0.50; levels[1].always = true;
   levels[2].name = "Q3";  levels[2].frac = 0.75; levels[2].always = false;

   for(int k = 0; k < 3; k++)
   {
      if(!levels[k].always && !InpShowInternal) continue;

      double pL = LowerAt(time[leftBar]) + g_chanWidth * levels[k].frac;
      double pR = LowerAt(time[0])       + g_chanWidth * levels[k].frac;

      ENUM_LINE_STYLE ls = levels[k].always ? STYLE_DASH : STYLE_DOT;
      string nm = g_pfx + "INT" + levels[k].name;

      ObjectCreate(0, nm, OBJ_TREND, 0, time[leftBar], pL, time[0], pR);
      ObjectSetInteger(0, nm, OBJPROP_COLOR,     C'120,120,120');
      ObjectSetInteger(0, nm, OBJPROP_WIDTH,      1);
      ObjectSetInteger(0, nm, OBJPROP_STYLE,      ls);
      ObjectSetInteger(0, nm, OBJPROP_RAY_RIGHT,  true);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nm, OBJPROP_BACK,       true);
   }
}

//+------------------------------------------------------------------+
// Score, sort, and draw horizontal S/R zones
//+------------------------------------------------------------------+
void DrawZones(const datetime &time[], int total)
{
   for(int z = 0; z < g_nZones; z++)
   {
      if(!g_zones[z].valid || g_zones[z].touches < InpMinTouches)
         { g_zones[z].score = -1; continue; }
      double recency = 1.0 / (1.0 + g_zones[z].firstBar * 0.005);
      g_zones[z].score = g_zones[z].touches * 4.0 + recency * 2.0;
   }

   // Sort descending
   for(int a = 0; a < g_nZones - 1; a++)
      for(int b = a + 1; b < g_nZones; b++)
         if(g_zones[b].score > g_zones[a].score)
         {
            SZone tmp = g_zones[a]; g_zones[a] = g_zones[b]; g_zones[b] = tmp;
         }

   int drawn = 0;
   for(int z = 0; z < g_nZones && drawn < InpMaxZones; z++)
   {
      if(!g_zones[z].valid || g_zones[z].score <= 0 || g_zones[z].touches < InpMinTouches) continue;

      int    leftBar = MathMin(g_zones[z].firstBar + InpPivotStr * 2, total - 1);
      color  zc      = g_zones[z].isResist ? InpResCol : InpSuptCol;
      string nm      = g_pfx + "Z" + IntegerToString(z);

      ObjectCreate(0, nm, OBJ_RECTANGLE, 0,
                   time[leftBar], g_zones[z].top,
                   time[0],       g_zones[z].bot);
      ObjectSetInteger(0, nm, OBJPROP_COLOR,     zc);
      ObjectSetInteger(0, nm, OBJPROP_FILL,       true);
      ObjectSetInteger(0, nm, OBJPROP_BACK,       true);
      ObjectSetInteger(0, nm, OBJPROP_WIDTH,       1);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE,  false);

      string lbl = (g_zones[z].isResist ? "RESISTANCE" : "SUPPORT")
                 + "  [" + IntegerToString(g_zones[z].touches) + "T]";
      string lnm = g_pfx + "ZL" + IntegerToString(z);
      ObjectCreate(0, lnm, OBJ_TEXT, 0, time[leftBar], g_zones[z].top);
      ObjectSetString(0,  lnm, OBJPROP_TEXT,      lbl);
      ObjectSetInteger(0, lnm, OBJPROP_COLOR,     zc);
      ObjectSetInteger(0, lnm, OBJPROP_FONTSIZE,  7);
      ObjectSetString(0,  lnm, OBJPROP_FONT,      "Consolas");
      ObjectSetInteger(0, lnm, OBJPROP_SELECTABLE, false);
      drawn++;
   }
}

//+------------------------------------------------------------------+
// Alert when price is near a detected zone
//+------------------------------------------------------------------+
void CheckAlerts(double price, double atr)
{
   static datetime lastAlert = 0;
   datetime bt = iTime(_Symbol, _Period, 0);
   if(bt == lastAlert) return;
   double tol = atr * InpAlertAtr;
   for(int z = 0; z < g_nZones && z < InpMaxZones; z++)
   {
      if(!g_zones[z].valid || g_zones[z].touches < InpMinTouches) continue;
      if(price >= g_zones[z].bot - tol && price <= g_zones[z].top + tol)
      {
         Alert(_Symbol + " [STM] " +
               (g_zones[z].isResist ? "RESISTANCE" : "SUPPORT") +
               " zone @ " + DoubleToString(g_zones[z].price, _Digits));
         lastAlert = bt;
         return;
      }
   }
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

   ArraySetAsSeries(high,  true);
   ArraySetAsSeries(low,   true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(time,  true);

   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(g_atr, 0, 0, rates_total, atr) <= 0) return prev_calculated;

   // Always re-read channel so user adjustments take effect immediately
   static double prevUpperA = 0, prevSlope = 0;
   g_chanOk = ReadChannel();

   bool chanChanged = g_chanOk &&
                      (MathAbs(g_chanUpperA - prevUpperA) > 1e-8 ||
                       MathAbs(g_chanSlope  - prevSlope)  > 1e-14);
   if(chanChanged) { prevUpperA = g_chanUpperA; prevSlope = g_chanSlope; }

   // Full recalc on new bar, on first run, or when channel was adjusted
   bool fullCalc = (prev_calculated == 0 || prev_calculated < rates_total || chanChanged);
   if(!fullCalc) return rates_total;

   DeleteObjects();

   if(!g_chanOk)
   {
      if(InpShowDash) UpdateDash(0, 0);
      ChartRedraw(0);
      return rates_total;
   }

   DetectZones(high, low, atr, time, rates_total);
   DrawInternalLines(time, rates_total);
   DrawZones(time, rates_total);

   if(InpAlerts)   CheckAlerts(close[0], atr[0]);
   if(InpShowDash) UpdateDash(close[0], atr[0]);

   ChartRedraw(0);
   return rates_total;
}

//+------------------------------------------------------------------+
// Dashboard                                                          |
//+------------------------------------------------------------------+
void CreateLabel(const string name, int x, int y, int sz = 8)
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_CORNER,     CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, name, OBJPROP_COLOR,      clrSilver);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,   sz);
   ObjectSetString(0,  name, OBJPROP_FONT,       "Consolas");
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_BACK,       false);
   ObjectSetInteger(0, name, OBJPROP_ZORDER,     2);
}

void CreateDash()
{
   ObjectCreate(0, g_pfx+"BG", OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, g_pfx+"BG", OBJPROP_CORNER,      CORNER_LEFT_UPPER);
   ObjectSetInteger(0, g_pfx+"BG", OBJPROP_XDISTANCE,   8);
   ObjectSetInteger(0, g_pfx+"BG", OBJPROP_YDISTANCE,   28);
   ObjectSetInteger(0, g_pfx+"BG", OBJPROP_XSIZE,       220);
   ObjectSetInteger(0, g_pfx+"BG", OBJPROP_YSIZE,       133);
   ObjectSetInteger(0, g_pfx+"BG", OBJPROP_BGCOLOR,     C'8,8,18');
   ObjectSetInteger(0, g_pfx+"BG", OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, g_pfx+"BG", OBJPROP_COLOR,       C'35,35,75');
   ObjectSetInteger(0, g_pfx+"BG", OBJPROP_SELECTABLE,  false);
   ObjectSetInteger(0, g_pfx+"BG", OBJPROP_BACK,        false);
   ObjectSetInteger(0, g_pfx+"BG", OBJPROP_ZORDER,      1);

   CreateLabel(g_pfx+"TITLE",  16, 35, 9);
   CreateLabel(g_pfx+"STATUS", 16, 55);
   CreateLabel(g_pfx+"DIR",    16, 70);
   CreateLabel(g_pfx+"WIDTH",  16, 85);
   CreateLabel(g_pfx+"ZONES",  16, 100);
   CreateLabel(g_pfx+"POS",    16, 115);
   CreateLabel(g_pfx+"NEAR",   16, 130);

   ObjectSetString(0,  g_pfx+"TITLE", OBJPROP_TEXT,  "  S/R INSIDE CHANNEL");
   ObjectSetInteger(0, g_pfx+"TITLE", OBJPROP_COLOR, clrDodgerBlue);
}

void UpdateDash(double price, double atr)
{
   if(!g_chanOk)
   {
      ObjectSetString(0,  g_pfx+"STATUS", OBJPROP_TEXT,  "Draw OBJ_CHANNEL on chart");
      ObjectSetInteger(0, g_pfx+"STATUS", OBJPROP_COLOR, clrTomato);
      string clearKeys[] = {"DIR","WIDTH","ZONES","POS","NEAR"};
      for(int _k = 0; _k < 5; _k++)
         ObjectSetString(0, g_pfx+clearKeys[_k], OBJPROP_TEXT, "");
      return;
   }

   datetime now = iTime(_Symbol, _Period, 0);
   double up    = UpperAt(now);
   double lo    = LowerAt(now);
   double rng   = up - lo;
   double pos   = (rng > 1e-10) ? (price - lo) / rng * 100.0 : 50.0;
   pos = MathMax(0.0, MathMin(100.0, pos));

   string posZone = (pos > 70) ? "HIGH  ↑" : (pos < 30 ? "LOW   ↓" : "MID   ~");
   color  posCol  = (pos > 70) ? clrTomato : (pos < 30 ? clrLime : clrGold);
   double atrW    = (atr > 1e-10) ? rng / atr : 0.0;

   string dir  = g_ascending ? "ASCENDING  ▲  →  SUPPORT zones"
                             : "DESCENDING ▼  →  RESISTANCE zones";
   color  dirC = g_ascending ? clrDodgerBlue : clrTomato;

   int validZ = 0;
   for(int z = 0; z < g_nZones; z++)
      if(g_zones[z].valid && g_zones[z].touches >= InpMinTouches) validZ++;

   ObjectSetString(0,  g_pfx+"STATUS", OBJPROP_TEXT,  "Channel  OK");
   ObjectSetInteger(0, g_pfx+"STATUS", OBJPROP_COLOR, clrLime);
   ObjectSetString(0,  g_pfx+"DIR",    OBJPROP_TEXT,  dir);
   ObjectSetInteger(0, g_pfx+"DIR",    OBJPROP_COLOR, dirC);
   ObjectSetString(0,  g_pfx+"WIDTH",  OBJPROP_TEXT,  StringFormat("Width   %.5f  (%.1f ATR)", rng, atrW));
   ObjectSetString(0,  g_pfx+"ZONES",  OBJPROP_TEXT,  StringFormat("Zones   %d valid / %d found", validZ, g_nZones));
   ObjectSetString(0,  g_pfx+"POS",    OBJPROP_TEXT,  StringFormat("Pos     %.0f%%  %s", pos, posZone));
   ObjectSetInteger(0, g_pfx+"POS",    OBJPROP_COLOR, posCol);

   double closest    = 1e10;
   string closestStr = "---";
   for(int z = 0; z < g_nZones && z < InpMaxZones; z++)
   {
      if(!g_zones[z].valid || g_zones[z].touches < InpMinTouches) continue;
      double d = MathAbs(price - g_zones[z].price);
      if(d < closest) { closest = d; closestStr = DoubleToString(g_zones[z].price, _Digits); }
   }
   ObjectSetString(0, g_pfx+"NEAR", OBJPROP_TEXT, "Nearest  " + closestStr);
}

//+------------------------------------------------------------------+
// Cleanup                                                            |
//+------------------------------------------------------------------+
void DeleteObjects()
{
   string keep[] = {"BG","TITLE","STATUS","DIR","WIDTH","ZONES","POS","NEAR"};
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i, 0, -1);
      if(StringFind(nm, g_pfx) != 0) continue;
      bool isDash = false;
      for(int d = 0; d < ArraySize(keep); d++)
         if(nm == g_pfx + keep[d]) { isDash = true; break; }
      if(!isDash) ObjectDelete(0, nm);
   }
}

void DeleteAllObjects()
{
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i, 0, -1);
      if(StringFind(nm, g_pfx) == 0) ObjectDelete(0, nm);
   }
   ChartRedraw(0);
}
//+------------------------------------------------------------------+
