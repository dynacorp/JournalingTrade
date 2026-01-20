//+------------------------------------------------------------------+
//|                                            ChartSnapshotEA.mq5   |
//|                                    TradeMind Chart Analysis EA   |
//|                             Captures and sends chart screenshots |
//+------------------------------------------------------------------+
#property copyright "TradeMind"
#property link      ""
#property version   "3.00"
#property strict

//--- Input parameters
input string   InpServerURL = "http://localhost:3000";     // Server URL
input string   InpIngestionKey = "";                        // Ingestion Key (from MT5 Account settings)
input int      InpImageWidth = 1920;                        // Screenshot width
input int      InpImageHeight = 1080;                       // Screenshot height
input bool     InpShowIndicators = true;                    // Include indicators in screenshot

//--- Multi-timeframe settings
input string   InpHTFTimeframes = "H1,H4";                  // Higher Timeframes (bias/structure)
input string   InpLTFTimeframes = "M5,M15";                 // Lower Timeframes (entry)
input bool     InpGroupedCapture = true;                    // Capture all TFs together as group

//--- Global variables
string   g_htfTimeframes[];
string   g_ltfTimeframes[];
int      g_htfCount = 0;
int      g_ltfCount = 0;

// Track last bar time for each monitored timeframe to detect candle close
datetime g_lastBarTime[];
string   g_monitoredTFs[];
int      g_monitoredCount = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Validate ingestion key
   if(StringLen(InpIngestionKey) == 0)
   {
      Print("ERROR: Ingestion Key is required. Get it from TradeMind Settings > MT5 Accounts");
      return INIT_PARAMETERS_INCORRECT;
   }

   //--- Parse timeframes
   g_htfCount = StringSplit(InpHTFTimeframes, ',', g_htfTimeframes);
   g_ltfCount = StringSplit(InpLTFTimeframes, ',', g_ltfTimeframes);

   if(g_htfCount == 0 && g_ltfCount == 0)
   {
      Print("ERROR: No valid timeframes specified");
      return INIT_PARAMETERS_INCORRECT;
   }

   //--- Trim whitespace from timeframes
   for(int i = 0; i < g_htfCount; i++)
   {
      StringTrimLeft(g_htfTimeframes[i]);
      StringTrimRight(g_htfTimeframes[i]);
   }
   for(int i = 0; i < g_ltfCount; i++)
   {
      StringTrimLeft(g_ltfTimeframes[i]);
      StringTrimRight(g_ltfTimeframes[i]);
   }

   //--- Build combined list of monitored timeframes
   g_monitoredCount = g_htfCount + g_ltfCount;
   ArrayResize(g_monitoredTFs, g_monitoredCount);
   ArrayResize(g_lastBarTime, g_monitoredCount);

   int idx = 0;
   for(int i = 0; i < g_htfCount; i++)
   {
      g_monitoredTFs[idx] = g_htfTimeframes[i];
      g_lastBarTime[idx] = 0;
      idx++;
   }
   for(int i = 0; i < g_ltfCount; i++)
   {
      g_monitoredTFs[idx] = g_ltfTimeframes[i];
      g_lastBarTime[idx] = 0;
      idx++;
   }

   Print("ChartSnapshotEA v3.0 initialized - Candle Close Mode");
   Print("Server: ", InpServerURL);
   Print("HTF (bias): ", InpHTFTimeframes);
   Print("LTF (entry): ", InpLTFTimeframes);
   Print("Grouped capture: ", InpGroupedCapture ? "Yes" : "No");
   Print("Captures only on candle close for each timeframe");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("ChartSnapshotEA deinitialized");
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Check each monitored timeframe for candle close
   for(int i = 0; i < g_monitoredCount; i++)
   {
      ENUM_TIMEFRAMES tf = StringToTimeframe(g_monitoredTFs[i]);
      datetime currentBarTime = iTime(_Symbol, tf, 0);

      //--- New bar detected = previous candle closed
      if(currentBarTime != g_lastBarTime[i] && g_lastBarTime[i] != 0)
      {
         //--- Get the closed candle's time (bar index 1)
         datetime closedCandleTime = iTime(_Symbol, tf, 1);

         //--- Determine if this is HTF or LTF
         string tfType = IsHTF(g_monitoredTFs[i]) ? "htf" : "ltf";

         Print("Candle closed: ", _Symbol, " ", g_monitoredTFs[i], " at ", TimeToString(closedCandleTime));

         if(InpGroupedCapture)
         {
            //--- Check if this is the "anchor" timeframe for the group (smallest monitored TF)
            //--- Only trigger group capture on smallest TF close to avoid multiple group captures
            if(IsSmallestMonitoredTF(g_monitoredTFs[i]))
            {
               CaptureGroupedSnapshots(closedCandleTime);
            }
         }
         else
         {
            //--- Capture just this timeframe
            CaptureTimeframe(_Symbol, tf, g_monitoredTFs[i], "", tfType, closedCandleTime);
         }
      }

      g_lastBarTime[i] = currentBarTime;
   }
}

//+------------------------------------------------------------------+
//| Check if timeframe is HTF                                          |
//+------------------------------------------------------------------+
bool IsHTF(string tf)
{
   for(int i = 0; i < g_htfCount; i++)
   {
      if(g_htfTimeframes[i] == tf)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Check if this is the smallest monitored timeframe                  |
//+------------------------------------------------------------------+
bool IsSmallestMonitoredTF(string tf)
{
   int tfMinutes = TimeframeToMinutes(tf);

   for(int i = 0; i < g_monitoredCount; i++)
   {
      int otherMinutes = TimeframeToMinutes(g_monitoredTFs[i]);
      if(otherMinutes < tfMinutes)
         return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| Convert timeframe string to minutes                                |
//+------------------------------------------------------------------+
int TimeframeToMinutes(string tf)
{
   if(tf == "M1")  return 1;
   if(tf == "M2")  return 2;
   if(tf == "M3")  return 3;
   if(tf == "M4")  return 4;
   if(tf == "M5")  return 5;
   if(tf == "M6")  return 6;
   if(tf == "M10") return 10;
   if(tf == "M12") return 12;
   if(tf == "M15") return 15;
   if(tf == "M20") return 20;
   if(tf == "M30") return 30;
   if(tf == "H1")  return 60;
   if(tf == "H2")  return 120;
   if(tf == "H3")  return 180;
   if(tf == "H4")  return 240;
   if(tf == "H6")  return 360;
   if(tf == "H8")  return 480;
   if(tf == "H12") return 720;
   if(tf == "D1")  return 1440;
   if(tf == "W1")  return 10080;
   if(tf == "MN1") return 43200;
   return 15; // Default
}

//+------------------------------------------------------------------+
//| Capture all timeframes as a group                                  |
//+------------------------------------------------------------------+
void CaptureGroupedSnapshots(datetime triggerCandleTime)
{
   string symbol = _Symbol;
   long originalChartId = ChartID();
   ENUM_TIMEFRAMES originalTF = ChartPeriod(originalChartId);

   //--- Generate group ID for linking all snapshots
   string groupId = GenerateGroupId();

   Print("Starting grouped capture for ", symbol, " (Group: ", groupId, ")");

   //--- Capture HTF snapshots first (for bias/structure)
   for(int i = 0; i < g_htfCount; i++)
   {
      ENUM_TIMEFRAMES tf = StringToTimeframe(g_htfTimeframes[i]);
      if(tf != PERIOD_CURRENT)
      {
         //--- Get the current candle time for this HTF
         datetime htfCandleTime = iTime(symbol, tf, 0);
         CaptureTimeframe(symbol, tf, g_htfTimeframes[i], groupId, "htf", htfCandleTime);
         Sleep(500); // Brief pause between captures
      }
   }

   //--- Capture LTF snapshots (for entry)
   for(int i = 0; i < g_ltfCount; i++)
   {
      ENUM_TIMEFRAMES tf = StringToTimeframe(g_ltfTimeframes[i]);
      if(tf != PERIOD_CURRENT)
      {
         //--- Get the current candle time for this LTF
         datetime ltfCandleTime = iTime(symbol, tf, 0);
         CaptureTimeframe(symbol, tf, g_ltfTimeframes[i], groupId, "ltf", ltfCandleTime);
         Sleep(500);
      }
   }

   //--- Restore original timeframe
   ChartSetSymbolPeriod(originalChartId, symbol, originalTF);

   Print("Grouped capture complete. Group ID: ", groupId);
}

//+------------------------------------------------------------------+
//| Capture a specific timeframe                                       |
//+------------------------------------------------------------------+
void CaptureTimeframe(string symbol, ENUM_TIMEFRAMES tf, string tfString,
                      string groupId, string tfType, datetime candleTime)
{
   long chartId = ChartID();

   //--- Switch chart to target timeframe
   if(!ChartSetSymbolPeriod(chartId, symbol, tf))
   {
      Print("ERROR: Failed to switch to ", tfString);
      return;
   }

   //--- Wait for chart to update
   Sleep(1000);
   ChartRedraw(chartId);
   Sleep(500);

   //--- Generate snapshot ID based on symbol + timeframe + candle time (for upsert)
   string snapshotId = GenerateSnapshotId(symbol, tfString, candleTime);

   //--- Capture screenshot
   string filename = "snapshot_" + snapshotId + ".png";

   if(!CaptureChartScreenshot(filename))
   {
      Print("ERROR: Failed to capture ", tfString, " screenshot");
      return;
   }

   //--- Read and encode
   string base64Data = FileToBase64(filename);
   if(StringLen(base64Data) == 0)
   {
      Print("ERROR: Failed to read screenshot file for ", tfString);
      FileDelete(filename);
      return;
   }

   //--- Build and send
   string json = BuildJsonPayload(snapshotId, symbol, tfString, base64Data, groupId, tfType, candleTime);

   if(SendToServer(json))
   {
      Print("Sent: ", symbol, " ", tfString, " (", tfType, ") candle: ", TimeToString(candleTime));
   }
   else
   {
      Print("ERROR: Failed to send ", tfString, " snapshot");
   }

   //--- Cleanup
   FileDelete(filename);
}

//+------------------------------------------------------------------+
//| Capture chart to PNG file                                          |
//+------------------------------------------------------------------+
bool CaptureChartScreenshot(string filename)
{
   long chartId = ChartID();

   bool result = ChartScreenShot(chartId, filename, InpImageWidth, InpImageHeight, ALIGN_RIGHT);

   if(!result)
   {
      Print("ChartScreenShot failed. Error: ", GetLastError());
   }

   return result;
}

//+------------------------------------------------------------------+
//| Convert file to Base64 string                                      |
//+------------------------------------------------------------------+
string FileToBase64(string filename)
{
   int handle = FileOpen(filename, FILE_READ | FILE_BIN);
   if(handle == INVALID_HANDLE)
   {
      Print("FileOpen failed for: ", filename, " Error: ", GetLastError());
      return "";
   }

   ulong fileSize = FileSize(handle);
   if(fileSize == 0 || fileSize > 10 * 1024 * 1024)
   {
      Print("Invalid file size: ", fileSize);
      FileClose(handle);
      return "";
   }

   uchar data[];
   ArrayResize(data, (int)fileSize);
   uint bytesRead = FileReadArray(handle, data);
   FileClose(handle);

   if(bytesRead != fileSize)
   {
      Print("FileReadArray incomplete: ", bytesRead, " vs ", fileSize);
      return "";
   }

   uchar key[], result[];
   int encodedLen = CryptEncode(CRYPT_BASE64, data, key, result);

   if(encodedLen <= 0)
   {
      Print("Base64 encoding failed");
      return "";
   }

   return CharArrayToString(result);
}

//+------------------------------------------------------------------+
//| Build JSON payload for API                                         |
//+------------------------------------------------------------------+
string BuildJsonPayload(string snapshotId, string symbol, string timeframe,
                        string imageBase64, string groupId, string tfType, datetime candleTime)
{
   //--- Current timestamp in ISO format
   string timestamp = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
   StringReplace(timestamp, ".", "-");
   StringReplace(timestamp, " ", "T");
   timestamp += "Z";

   //--- Candle time in ISO format
   string candleTimeStr = TimeToString(candleTime, TIME_DATE | TIME_SECONDS);
   StringReplace(candleTimeStr, ".", "-");
   StringReplace(candleTimeStr, " ", "T");
   candleTimeStr += "Z";

   //--- Build JSON
   string json = "{";
   json += "\"snapshot_id\":\"" + snapshotId + "\",";
   json += "\"symbol\":\"" + symbol + "\",";
   json += "\"timeframe\":\"" + timeframe + "\",";
   json += "\"snapshot_time\":\"" + timestamp + "\",";
   json += "\"candle_time\":\"" + candleTimeStr + "\",";
   json += "\"image_data\":\"" + imageBase64 + "\"";

   //--- Add group info if present
   if(StringLen(groupId) > 0)
   {
      json += ",\"group_id\":\"" + groupId + "\"";
      json += ",\"tf_type\":\"" + tfType + "\"";
   }

   json += "}";

   return json;
}

//+------------------------------------------------------------------+
//| Send JSON payload to server                                        |
//+------------------------------------------------------------------+
bool SendToServer(string json)
{
   string url = InpServerURL + "/api/chart-snapshots/ingest";
   string headers = "Content-Type: application/json\r\nAuthorization: Bearer " + InpIngestionKey;

   char jsonData[];
   StringToCharArray(json, jsonData, 0, StringLen(json));

   char result[];
   string resultHeaders;

   int timeout = 30000;
   int responseCode = WebRequest(
      "POST",
      url,
      headers,
      timeout,
      jsonData,
      result,
      resultHeaders
   );

   if(responseCode == -1)
   {
      int error = GetLastError();
      Print("WebRequest failed. Error: ", error);

      if(error == 4014)
      {
         Print("IMPORTANT: Add '", InpServerURL, "' to Tools > Options > Expert Advisors > Allow WebRequest for listed URL");
      }

      return false;
   }

   string response = CharArrayToString(result);

   if(responseCode == 200 || responseCode == 201)
   {
      return true;
   }
   else if(responseCode == 409)
   {
      return true; // Duplicate, not an error
   }
   else if(responseCode == 401)
   {
      Print("Server response (401): Invalid ingestion key");
      return false;
   }
   else
   {
      Print("Server response (", responseCode, "): ", response);
      return false;
   }
}

//+------------------------------------------------------------------+
//| Generate deterministic snapshot ID based on symbol+tf+candle       |
//+------------------------------------------------------------------+
string GenerateSnapshotId(string symbol, string timeframe, datetime candleTime)
{
   //--- Create deterministic ID: symbol_timeframe_candleTimestamp
   //--- This allows server to upsert based on this key
   string id = symbol + "_" + timeframe + "_" + IntegerToString((long)candleTime);

   //--- Hash it to keep it shorter and URL-safe
   uint hash = 0;
   for(int i = 0; i < StringLen(id); i++)
   {
      hash = hash * 31 + StringGetCharacter(id, i);
   }

   return IntegerToString((long)candleTime) + "_" + timeframe + "_" + IntegerToString(hash);
}

//+------------------------------------------------------------------+
//| Generate group ID for MTF snapshots                                |
//+------------------------------------------------------------------+
string GenerateGroupId()
{
   string id = "grp_";
   id += IntegerToString(TimeCurrent());
   id += "_" + _Symbol;
   id += "_" + IntegerToString(MathRand() % 10000);
   return id;
}

//+------------------------------------------------------------------+
//| Convert string to ENUM_TIMEFRAMES                                  |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES StringToTimeframe(string tf)
{
   if(tf == "M1")  return PERIOD_M1;
   if(tf == "M2")  return PERIOD_M2;
   if(tf == "M3")  return PERIOD_M3;
   if(tf == "M4")  return PERIOD_M4;
   if(tf == "M5")  return PERIOD_M5;
   if(tf == "M6")  return PERIOD_M6;
   if(tf == "M10") return PERIOD_M10;
   if(tf == "M12") return PERIOD_M12;
   if(tf == "M15") return PERIOD_M15;
   if(tf == "M20") return PERIOD_M20;
   if(tf == "M30") return PERIOD_M30;
   if(tf == "H1")  return PERIOD_H1;
   if(tf == "H2")  return PERIOD_H2;
   if(tf == "H3")  return PERIOD_H3;
   if(tf == "H4")  return PERIOD_H4;
   if(tf == "H6")  return PERIOD_H6;
   if(tf == "H8")  return PERIOD_H8;
   if(tf == "H12") return PERIOD_H12;
   if(tf == "D1")  return PERIOD_D1;
   if(tf == "W1")  return PERIOD_W1;
   if(tf == "MN1") return PERIOD_MN1;
   return PERIOD_CURRENT;
}

//+------------------------------------------------------------------+
//| Manual capture function (can be called from button/hotkey)         |
//+------------------------------------------------------------------+
void ManualCapture()
{
   datetime now = TimeCurrent();
   if(InpGroupedCapture)
      CaptureGroupedSnapshots(now);
   else
   {
      ENUM_TIMEFRAMES tf = ChartPeriod(ChartID());
      string tfStr = "";
      for(int i = 0; i < g_monitoredCount; i++)
      {
         if(StringToTimeframe(g_monitoredTFs[i]) == tf)
         {
            tfStr = g_monitoredTFs[i];
            break;
         }
      }
      if(StringLen(tfStr) > 0)
      {
         string tfType = IsHTF(tfStr) ? "htf" : "ltf";
         CaptureTimeframe(_Symbol, tf, tfStr, "", tfType, iTime(_Symbol, tf, 0));
      }
   }
}
//+------------------------------------------------------------------+
