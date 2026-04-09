//+------------------------------------------------------------------+
//|                                                  WickMeasure.mq5  |
//|                        TradeMind Wick Size Indicator               |
//|  Displays upper and lower wick sizes vertically on each candle.   |
//+------------------------------------------------------------------+
#property copyright "TradeMind"
#property link      ""
#property version   "1.00"
#property strict
#property indicator_chart_window
#property indicator_plots 0

//+------------------------------------------------------------------+
//| Input Parameters                                                   |
//+------------------------------------------------------------------+
input group "=== Display ==="
input int      InpMaxBars          = 100;        // Max bars to label
input int      InpFontSize         = 7;          // Font size
input double   InpMinWickSize      = 10.0;       // Min wick size to show (price units, 0=all)
input bool     InpShowUpperWick    = true;       // Show upper wick size
input bool     InpShowLowerWick    = true;       // Show lower wick size

input group "=== Colors ==="
input color    InpUpperWickColor   = clrDodgerBlue;  // Upper wick color
input color    InpLowerWickColor   = clrOrange;      // Lower wick color

//+------------------------------------------------------------------+
//| Globals                                                            |
//+------------------------------------------------------------------+
string g_prefix = "WM_";
int    g_lastCalculatedBars = 0;

//+------------------------------------------------------------------+
//| OnInit                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
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
   if(rates_total < 2) return rates_total;

   //--- New bar guard
   if(rates_total == g_lastCalculatedBars) return rates_total;
   g_lastCalculatedBars = rates_total;

   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int limit = MathMin(rates_total - 1, InpMaxBars);

   CleanAllObjects();

   //--- Calculate ATR for offset spacing
   double atrOffset = 0;
   if(limit > 14)
   {
      double sum = 0;
      for(int j = 1; j <= 14; j++)
         sum += high[j] - low[j];
      atrOffset = (sum / 14) * 0.15;
   }

   for(int i = 1; i <= limit; i++)
   {
      double body_top    = MathMax(open[i], close[i]);
      double body_bottom = MathMin(open[i], close[i]);
      double upper_wick  = high[i] - body_top;
      double lower_wick  = body_bottom - low[i];

      //--- Upper wick label
      if(InpShowUpperWick && upper_wick > InpMinWickSize)
      {
         string text = FormatWick(upper_wick, digits, point);
         string name = g_prefix + "U_" + IntegerToString(i);
         double yPrice = high[i] + atrOffset;

         if(!ObjectCreate(0, name, OBJ_TEXT, 0, time[i], yPrice))
            ObjectMove(0, name, 0, time[i], yPrice);

         ObjectSetString(0, name, OBJPROP_TEXT, text);
         ObjectSetInteger(0, name, OBJPROP_COLOR, InpUpperWickColor);
         ObjectSetString(0, name, OBJPROP_FONT, "Arial");
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpFontSize);
         ObjectSetDouble(0, name, OBJPROP_ANGLE, 90.0);
         ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LOWER);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      }

      //--- Lower wick label
      if(InpShowLowerWick && lower_wick > InpMinWickSize)
      {
         string text = FormatWick(lower_wick, digits, point);
         string name = g_prefix + "L_" + IntegerToString(i);
         double yPrice = low[i] - atrOffset;

         if(!ObjectCreate(0, name, OBJ_TEXT, 0, time[i], yPrice))
            ObjectMove(0, name, 0, time[i], yPrice);

         ObjectSetString(0, name, OBJPROP_TEXT, text);
         ObjectSetInteger(0, name, OBJPROP_COLOR, InpLowerWickColor);
         ObjectSetString(0, name, OBJPROP_FONT, "Arial");
         ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpFontSize);
         ObjectSetDouble(0, name, OBJPROP_ANGLE, 90.0);
         ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_UPPER);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      }
   }

   return rates_total;
}

//+------------------------------------------------------------------+
//| FormatWick — format wick size as readable string                    |
//+------------------------------------------------------------------+
string FormatWick(double wickSize, int digits, double point)
{
   //--- Show in points for small values, price units otherwise
   if(digits <= 3)
      return DoubleToString(wickSize, digits);

   double points = wickSize / point;
   if(points < 100)
      return DoubleToString(points, 1) + "p";
   else
      return IntegerToString((int)MathRound(points)) + "p";
}

//+------------------------------------------------------------------+
//| CleanAllObjects                                                    |
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
