//+------------------------------------------------------------------+
//| PAM/KillZoneEngine.mqh  —  ICT Kill Zone Time Windows           |
//|                                                                  |
//| SMC / ICT Core Concept:                                         |
//|   Kill zones are 2-3 hour windows where institutional activity   |
//|   concentrates. The majority of daily BOS / CHoCH / manipulation |
//|   events occur inside these windows — not randomly throughout    |
//|   the session. Recognising kill zone timing turns abstract SMC   |
//|   concepts into time-aware entries.                              |
//|                                                                  |
//|   LONDON OPEN KZ   07:00–10:00  — Asian range sweep, BOS,      |
//|                                    trend initiation for the day. |
//|   NEW YORK OPEN KZ 12:00–15:00  — Confirms or reverses London.  |
//|                                    Highest-probability expansion.|
//|   NEW YORK PM KZ   19:00–21:00  — Late reversals, position      |
//|                                    closing traps, NY close runs. |
//|   ASIAN KZ         20:00–23:00  — Quiet accumulation zone.      |
//|                                    Defines tomorrow's range.     |
//|                                                                  |
//| Each kill zone box shows the actual price HIGH/LOW reached       |
//| within that window — these become the liquidity pools that the   |
//| next session's kill zone targets.                                |
//+------------------------------------------------------------------+
#ifndef PAM_KILLZONE_MQH
#define PAM_KILLZONE_MQH
#include "Context.mqh"

//--- Kill zone type identifiers (internal)
enum EKillZone
{
   KZ_NONE     = 0,
   KZ_ASIAN,        // 20:00–23:00
   KZ_LONDON,       // 07:00–10:00
   KZ_NY_AM,        // 12:00–15:00
   KZ_NY_PM         // 19:00–21:00
};

//+------------------------------------------------------------------+
// GetKillZone
//   Returns which kill zone (if any) a given broker-hour falls in.
//   Priority: if hours overlap, NY_AM > LONDON > NY_PM > ASIAN.
//+------------------------------------------------------------------+
EKillZone GetKillZone(int hour, bool showLondon, bool showNYAM,
                                bool showNYPM,   bool showAsian)
{
   if(showNYAM   && hour >= 12 && hour < 15) return KZ_NY_AM;
   if(showLondon && hour >=  7 && hour < 10) return KZ_LONDON;
   if(showNYPM   && hour >= 19 && hour < 21) return KZ_NY_PM;
   if(showAsian  && hour >= 20 && hour < 23) return KZ_ASIAN;
   return KZ_NONE;
}

//+------------------------------------------------------------------+
// KillZoneEngine_Draw
//   Draws price-range boxes for each kill zone segment within the
//   last ctx.kzDays calendar days. Uses brighter borders than session
//   boxes so they read as "windows of opportunity" on top of sessions.
//+------------------------------------------------------------------+
void KillZoneEngine_Draw(const SPAMContext &ctx,
                          const datetime   &time[],
                          const double     &high[],
                          const double     &low[],
                          int               total,
                          const string     &pfx)
{
   if(!ctx.showKillZones) return;

   int limit = MathMin(ctx.lookback, total - 1);

   // Delete existing kill zone objects
   for(int obj = ObjectsTotal(0, 0, -1) - 1; obj >= 0; obj--)
   {
      string nm = ObjectName(0, obj, 0, -1);
      if(StringFind(nm, pfx + "KZ") == 0)
         ObjectDelete(0, nm);
   }

   EKillZone curKZ  = KZ_NONE;
   double    segHigh = -DBL_MAX;
   double    segLow  =  DBL_MAX;
   datetime  segStart = 0;
   datetime  segEnd   = 0;
   int       boxCount = 0;
   int       maxBoxes = ctx.kzDays * 6;

   for(int i = limit; i >= 0; i--)
   {
      MqlDateTime dt;
      TimeToStruct(time[i], dt);
      EKillZone thisKZ = GetKillZone(dt.hour,
                                     ctx.showLondonKZ,
                                     ctx.showNYAMKZ,
                                     ctx.showNYPMKZ,
                                     ctx.showAsianKZ);

      if(thisKZ == curKZ && thisKZ != KZ_NONE)
      {
         segHigh = MathMax(segHigh, high[i]);
         segLow  = MathMin(segLow,  low[i]);
         segEnd  = time[i];
      }
      else
      {
         // Flush previous segment
         if(curKZ != KZ_NONE && boxCount < maxBoxes)
         {
            string nm  = pfx + "KZ" + IntegerToString((int)segStart);
            string lnm = pfx + "KZL" + IntegerToString((int)segStart);

            color borderCol, fillCol;
            string label;
            switch(curKZ)
            {
               case KZ_LONDON:
                  borderCol = C'220,200,0';
                  fillCol   = C'28,25,0';
                  label     = "LKZ";
                  break;
               case KZ_NY_AM:
                  borderCol = C'255,130,0';
                  fillCol   = C'32,16,0';
                  label     = "NYKZ";
                  break;
               case KZ_NY_PM:
                  borderCol = C'200,80,0';
                  fillCol   = C'25,10,0';
                  label     = "PMKZ";
                  break;
               case KZ_ASIAN:
                  borderCol = C'100,140,200';
                  fillCol   = C'8,12,28';
                  label     = "AKZ";
                  break;
               default:
                  borderCol = clrGray;
                  fillCol   = C'10,10,10';
                  label     = "";
                  break;
            }

            ObjectCreate(0, nm, OBJ_RECTANGLE, 0, segStart, segHigh, segEnd, segLow);
            ObjectSetInteger(0, nm, OBJPROP_COLOR,      borderCol);
            ObjectSetInteger(0, nm, OBJPROP_STYLE,      ctx.outlineMode ? STYLE_DOT : STYLE_SOLID);
            ObjectSetInteger(0, nm, OBJPROP_WIDTH,      1);
            ObjectSetInteger(0, nm, OBJPROP_FILL,       !ctx.outlineMode);
            ObjectSetInteger(0, nm, OBJPROP_BGCOLOR,    fillCol);
            ObjectSetInteger(0, nm, OBJPROP_BACK,       true);
            ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);

            ObjectCreate(0, lnm, OBJ_TEXT, 0, segStart, segHigh);
            ObjectSetString(0,  lnm, OBJPROP_TEXT,      label);
            ObjectSetInteger(0, lnm, OBJPROP_COLOR,     borderCol);
            ObjectSetInteger(0, lnm, OBJPROP_FONTSIZE,  6);
            ObjectSetString(0,  lnm, OBJPROP_FONT,      "Consolas");
            ObjectSetInteger(0, lnm, OBJPROP_ANCHOR,    ANCHOR_LOWER);
            ObjectSetInteger(0, lnm, OBJPROP_BACK,      true);
            ObjectSetInteger(0, lnm, OBJPROP_SELECTABLE,false);

            boxCount++;
         }

         curKZ    = thisKZ;
         segHigh  = (thisKZ != KZ_NONE) ? high[i] : -DBL_MAX;
         segLow   = (thisKZ != KZ_NONE) ? low[i]  :  DBL_MAX;
         segStart = time[i];
         segEnd   = time[i];
      }
   }

   // Flush final open segment
   if(curKZ != KZ_NONE && boxCount < maxBoxes)
   {
      string nm  = pfx + "KZ" + IntegerToString((int)segStart);
      string lnm = pfx + "KZL" + IntegerToString((int)segStart);

      color borderCol, fillCol;
      string label;
      switch(curKZ)
      {
         case KZ_LONDON: borderCol = C'220,200,0'; fillCol = C'28,25,0'; label = "LKZ";  break;
         case KZ_NY_AM:  borderCol = C'255,130,0'; fillCol = C'32,16,0'; label = "NYKZ"; break;
         case KZ_NY_PM:  borderCol = C'200,80,0';  fillCol = C'25,10,0'; label = "PMKZ"; break;
         case KZ_ASIAN:  borderCol = C'100,140,200'; fillCol = C'8,12,28'; label = "AKZ"; break;
         default:        borderCol = clrGray; fillCol = C'10,10,10'; label = ""; break;
      }

      ObjectCreate(0, nm, OBJ_RECTANGLE, 0, segStart, segHigh, segEnd, segLow);
      ObjectSetInteger(0, nm, OBJPROP_COLOR,      borderCol);
      ObjectSetInteger(0, nm, OBJPROP_STYLE,      STYLE_SOLID);
      ObjectSetInteger(0, nm, OBJPROP_WIDTH,      1);
      ObjectSetInteger(0, nm, OBJPROP_FILL,       true);
      ObjectSetInteger(0, nm, OBJPROP_BGCOLOR,    fillCol);
      ObjectSetInteger(0, nm, OBJPROP_BACK,       true);
      ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);

      ObjectCreate(0, lnm, OBJ_TEXT, 0, segStart, segHigh);
      ObjectSetString(0,  lnm, OBJPROP_TEXT,      label);
      ObjectSetInteger(0, lnm, OBJPROP_COLOR,     borderCol);
      ObjectSetInteger(0, lnm, OBJPROP_FONTSIZE,  6);
      ObjectSetString(0,  lnm, OBJPROP_FONT,      "Consolas");
      ObjectSetInteger(0, lnm, OBJPROP_ANCHOR,    ANCHOR_LOWER);
      ObjectSetInteger(0, lnm, OBJPROP_BACK,      true);
      ObjectSetInteger(0, lnm, OBJPROP_SELECTABLE,false);
   }
}

//+------------------------------------------------------------------+
// KillZoneEngine_IsActive
//   Returns true if any kill zone is currently live.
//+------------------------------------------------------------------+
bool KillZoneEngine_IsActive(const SPAMContext &ctx)
{
   if(!ctx.showKillZones) return false;
   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);
   return GetKillZone(dt.hour,
                      ctx.showLondonKZ, ctx.showNYAMKZ,
                      ctx.showNYPMKZ,  ctx.showAsianKZ) != KZ_NONE;
}

//+------------------------------------------------------------------+
// KillZoneEngine_CurrentString
//   Dashboard row: which kill zone (if any) is currently active.
//+------------------------------------------------------------------+
string KillZoneEngine_CurrentString(const SPAMContext &ctx)
{
   if(!ctx.showKillZones) return "  Kill Zones  hidden";

   datetime now = TimeCurrent();
   MqlDateTime dt;
   TimeToStruct(now, dt);

   EKillZone kz = GetKillZone(dt.hour,
                               ctx.showLondonKZ,
                               ctx.showNYAMKZ,
                               ctx.showNYPMKZ,
                               ctx.showAsianKZ);
   switch(kz)
   {
      case KZ_LONDON: return "  Kill Zone   LONDON OPEN  07-10  ← active";
      case KZ_NY_AM:  return "  Kill Zone   NY OPEN       12-15  ← active";
      case KZ_NY_PM:  return "  Kill Zone   NY PM CLOSE   19-21  ← active";
      case KZ_ASIAN:  return "  Kill Zone   ASIAN         20-23  ← active";
      default:        return "  Kill Zone   off-window";
   }
}

#endif // PAM_KILLZONE_MQH
