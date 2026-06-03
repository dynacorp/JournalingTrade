//+------------------------------------------------------------------+
//| PAM/MTFEngine.mqh  —  Multi-timeframe bias detection            |
//|                                                                  |
//| Loads HTF OHLC data, runs a lightweight pivot scan to detect    |
//| HTF trend direction, and populates ctx.htfTrend.                |
//|                                                                  |
//| Critical for teaching "trading with vs against the trend."      |
//+------------------------------------------------------------------+
#ifndef PAM_MTF_MQH
#define PAM_MTF_MQH
#include "Context.mqh"

//+------------------------------------------------------------------+
// MTFEngine_Init — call from OnInit()
//   Creates the HTF ATR indicator handle.
//+------------------------------------------------------------------+
bool MTFEngine_Init(SPAMContext &ctx)
{
   if(ctx.htf == PERIOD_CURRENT || ctx.htf == _Period)
   {
      ctx.htfTrend    = TREND_UNDEFINED;
      ctx.htfAtrHandle = INVALID_HANDLE;
      return true;
   }
   ctx.htfAtrHandle = iATR(_Symbol, ctx.htf, 14);
   return (ctx.htfAtrHandle != INVALID_HANDLE);
}

//+------------------------------------------------------------------+
// MTFEngine_Compute
//   Copies the last 200 HTF bars and runs a simplified pivot scan
//   to determine HTF trend (BULLISH / BEARISH / RANGING / UNDEFINED).
//   Updates ctx.htfTrend and ctx.atrHtf.
//+------------------------------------------------------------------+
void MTFEngine_Compute(SPAMContext &ctx)
{
   ctx.htfTrend = TREND_UNDEFINED;
   ctx.atrHtf   = 0;

   if(ctx.htfAtrHandle == INVALID_HANDLE) return;
   if(ctx.htf == PERIOD_CURRENT || ctx.htf == _Period) return;

   // --- Copy HTF bars ---
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, ctx.htf, 0, 200, rates);
   if(copied < 20) return;

   // --- Copy HTF ATR ---
   double htfAtr[];
   ArraySetAsSeries(htfAtr, true);
   if(CopyBuffer(ctx.htfAtrHandle, 0, 0, copied, htfAtr) <= 0) return;
   ctx.atrHtf = htfAtr[0];

   // --- Simple pivot scan on HTF data ---
   int pivStr = 3;   // coarser than current-TF pivStr
   int total  = copied;
   double lastH = 0, lastL = 0, prevH = 0, prevL = 0;
   int    hhCount = 0, hlCount = 0, lhCount = 0, llCount = 0;

   for(int i = pivStr; i < total - pivStr; i++)
   {
      // Pivot high check
      bool isPH = true;
      for(int k = 1; k <= pivStr && isPH; k++)
         if(rates[i - k].high >= rates[i].high || rates[i + k].high >= rates[i].high)
            isPH = false;

      // Pivot low check
      bool isPL = true;
      for(int k = 1; k <= pivStr && isPL; k++)
         if(rates[i - k].low <= rates[i].low || rates[i + k].low <= rates[i].low)
            isPL = false;

      if(isPH)
      {
         if(lastH > 0)
         {
            if(rates[i].high > lastH) hhCount++;
            else                      lhCount++;
         }
         prevH = lastH;
         lastH = rates[i].high;
      }
      if(isPL)
      {
         if(lastL > 0)
         {
            if(rates[i].low < lastL) llCount++;
            else                     hlCount++;
         }
         prevL = lastL;
         lastL = rates[i].low;
      }
   }

   // Determine HTF trend from swing counts
   bool bullScore = (hhCount > lhCount) && (hlCount > llCount);
   bool bearScore = (lhCount > hhCount) && (llCount > hlCount);

   if(bullScore && !bearScore)       ctx.htfTrend = TREND_BULLISH;
   else if(bearScore && !bullScore)  ctx.htfTrend = TREND_BEARISH;
   else if(hhCount + hlCount + lhCount + llCount > 4)
                                     ctx.htfTrend = TREND_RANGING;
   else                              ctx.htfTrend = TREND_UNDEFINED;
}

//+------------------------------------------------------------------+
// HTF alignment description for dashboard
//+------------------------------------------------------------------+
string MTFEngine_BiasString(const SPAMContext &ctx)
{
   string tfStr = EnumToString(ctx.htf);
   // Clean up "PERIOD_" prefix
   StringReplace(tfStr, "PERIOD_", "");

   string trendStr;
   switch(ctx.htfTrend)
   {
      case TREND_BULLISH:   trendStr = "BULLISH ▲"; break;
      case TREND_BEARISH:   trendStr = "BEARISH ▼"; break;
      case TREND_RANGING:   trendStr = "RANGING ~"; break;
      default:              trendStr = "UNDEFINED";  break;
   }
   return tfStr + ": " + trendStr;
}

string MTFEngine_AlignmentString(const SPAMContext &ctx)
{
   if(ctx.htfTrend == TREND_UNDEFINED || ctx.trend == TREND_UNDEFINED)
      return "No alignment data";

   if(ctx.trend == ctx.htfTrend)
      return "  ALIGNED ✓  — trend confirmed on HTF";

   if(ctx.htfTrend == TREND_RANGING)
      return "  HTF ranging — no clear bias";

   // Current move is counter-trend
   string counterDir = (ctx.htfTrend == TREND_BULLISH) ? "bearish" : "bullish";
   return "  DIVERGE ✗  — current " + counterDir + " move vs HTF";
}

#endif // PAM_MTF_MQH
