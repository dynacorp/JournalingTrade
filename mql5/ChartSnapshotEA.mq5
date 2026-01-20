//+------------------------------------------------------------------+
//|                                            ChartSnapshotEA.mq5   |
//|                                    TradeMind Chart Analysis EA   |
//|                             Captures and sends chart screenshots |
//+------------------------------------------------------------------+
#property copyright "TradeMind"
#property link      ""
#property version   "2.00"
#property strict

//--- Input parameters
input string   InpServerURL = "http://localhost:3000";     // Server URL
input string   InpIngestionKey = "";                        // Ingestion Key (from MT5 Account settings)
input int      InpCaptureIntervalMinutes = 15;              // Capture interval (minutes)
input bool     InpCaptureOnNewBar = true;                   // Also capture on new bar
input int      InpImageWidth = 1920;                        // Screenshot width
input int      InpImageHeight = 1080;                       // Screenshot height
input bool     InpShowIndicators = true;                    // Include indicators in screenshot

//--- Multi-timeframe settings
input string   InpHTFTimeframes = "H1,H4";                  // Higher Timeframes (bias/structure)
input string   InpLTFTimeframes = "M5,M15";                 // Lower Timeframes (entry)
input bool     InpGroupedCapture = true;                    // Capture all TFs together as group

//--- Global variables
datetime g_lastCaptureTime = 0;
datetime g_lastBarTime = 0;
string   g_htfTimeframes[];
string   g_ltfTimeframes[];
int      g_htfCount = 0;
int      g_ltfCount = 0;

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

   Print("ChartSnapshotEA v2.0 initialized");
   Print("Server: ", InpServerURL);
   Print("Capture interval: ", InpCaptureIntervalMinutes, " minutes");
   Print("HTF (bias): ", InpHTFTimeframes);
   Print("LTF (entry): ", InpLTFTimeframes);
   Print("Grouped capture: ", InpGroupedCapture ? "Yes" : "No");

   //--- Set timer for periodic captures
   if(InpCaptureIntervalMinutes > 0)
   {
      EventSetTimer(InpCaptureIntervalMinutes * 60);
   }

   //--- Initial capture after short delay
   EventSetMillisecondTimer(5000);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   Print("ChartSnapshotEA deinitialized");
}

//+------------------------------------------------------------------+
//| Timer function                                                     |
//+------------------------------------------------------------------+
void OnTimer()
{
   //--- Capture on timer interval
   if(InpGroupedCapture)
      CaptureGroupedSnapshots("timer");
   else
      CaptureCurrentTimeframe("timer");
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Check for new bar if enabled
   if(InpCaptureOnNewBar)
   {
      datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
      if(currentBarTime != g_lastBarTime)
      {
         g_lastBarTime = currentBarTime;

         //--- Only capture if enough time has passed (prevent spam)
         if(TimeCurrent() - g_lastCaptureTime >= 60)
         {
            if(InpGroupedCapture)
               CaptureGroupedSnapshots("new_bar");
            else
               CaptureCurrentTimeframe("new_bar");
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Capture all timeframes as a group                                  |
//+------------------------------------------------------------------+
void CaptureGroupedSnapshots(string trigger)
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
         CaptureTimeframe(symbol, tf, g_htfTimeframes[i], groupId, "htf", trigger);
         Sleep(500); // Brief pause between captures
      }
   }

   //--- Capture LTF snapshots (for entry)
   for(int i = 0; i < g_ltfCount; i++)
   {
      ENUM_TIMEFRAMES tf = StringToTimeframe(g_ltfTimeframes[i]);
      if(tf != PERIOD_CURRENT)
      {
         CaptureTimeframe(symbol, tf, g_ltfTimeframes[i], groupId, "ltf", trigger);
         Sleep(500);
      }
   }

   //--- Restore original timeframe
   ChartSetSymbolPeriod(originalChartId, symbol, originalTF);

   g_lastCaptureTime = TimeCurrent();
   Print("Grouped capture complete. Group ID: ", groupId);
}

//+------------------------------------------------------------------+
//| Capture a specific timeframe                                       |
//+------------------------------------------------------------------+
void CaptureTimeframe(string symbol, ENUM_TIMEFRAMES tf, string tfString,
                      string groupId, string tfType, string trigger)
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

   //--- Generate snapshot ID
   string snapshotId = GenerateSnapshotId();

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
   string json = BuildJsonPayload(snapshotId, symbol, tfString, base64Data, groupId, tfType);

   if(SendToServer(json))
   {
      Print("Sent: ", symbol, " ", tfString, " (", tfType, ") [", trigger, "]");
   }
   else
   {
      Print("ERROR: Failed to send ", tfString, " snapshot");
   }

   //--- Cleanup
   FileDelete(filename);
}

//+------------------------------------------------------------------+
//| Capture only current timeframe (non-grouped mode)                  |
//+------------------------------------------------------------------+
void CaptureCurrentTimeframe(string trigger)
{
   string symbol = _Symbol;
   string timeframe = GetTimeframeString(PERIOD_CURRENT);

   //--- Check if current TF is in any monitored list
   string tfType = "";
   if(IsInArray(timeframe, g_htfTimeframes, g_htfCount))
      tfType = "htf";
   else if(IsInArray(timeframe, g_ltfTimeframes, g_ltfCount))
      tfType = "ltf";
   else
      return; // Not a monitored timeframe

   //--- Generate IDs
   string snapshotId = GenerateSnapshotId();
   string groupId = ""; // No group in non-grouped mode

   //--- Capture
   string filename = "snapshot_" + snapshotId + ".png";

   if(!CaptureChartScreenshot(filename))
   {
      Print("ERROR: Failed to capture screenshot");
      return;
   }

   //--- Read and encode
   string base64Data = FileToBase64(filename);
   if(StringLen(base64Data) == 0)
   {
      Print("ERROR: Failed to read screenshot file");
      FileDelete(filename);
      return;
   }

   //--- Build and send
   string json = BuildJsonPayload(snapshotId, symbol, timeframe, base64Data, groupId, tfType);

   if(SendToServer(json))
   {
      g_lastCaptureTime = TimeCurrent();
      Print("Sent: ", symbol, " ", timeframe, " (", trigger, ")");
   }
   else
   {
      Print("ERROR: Failed to send snapshot");
   }

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
                        string imageBase64, string groupId, string tfType)
{
   //--- Current timestamp in ISO format
   string timestamp = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
   StringReplace(timestamp, ".", "-");
   StringReplace(timestamp, " ", "T");
   timestamp += "Z";

   //--- Build JSON
   string json = "{";
   json += "\"snapshot_id\":\"" + snapshotId + "\",";
   json += "\"symbol\":\"" + symbol + "\",";
   json += "\"timeframe\":\"" + timeframe + "\",";
   json += "\"snapshot_time\":\"" + timestamp + "\",";
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

   if(responseCode == 201)
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
//| Generate unique snapshot ID                                        |
//+------------------------------------------------------------------+
string GenerateSnapshotId()
{
   string id = IntegerToString(TimeCurrent());

   string sym = _Symbol;
   uint hash = 0;
   for(int i = 0; i < StringLen(sym); i++)
   {
      hash = hash * 31 + StringGetCharacter(sym, i);
   }
   id += "_" + IntegerToString(hash);
   id += "_" + IntegerToString(MathRand());

   return id;
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
//| Convert ENUM_TIMEFRAMES to string                                  |
//+------------------------------------------------------------------+
string GetTimeframeString(ENUM_TIMEFRAMES tf)
{
   switch(tf)
   {
      case PERIOD_M1:  return "M1";
      case PERIOD_M2:  return "M2";
      case PERIOD_M3:  return "M3";
      case PERIOD_M4:  return "M4";
      case PERIOD_M5:  return "M5";
      case PERIOD_M6:  return "M6";
      case PERIOD_M10: return "M10";
      case PERIOD_M12: return "M12";
      case PERIOD_M15: return "M15";
      case PERIOD_M20: return "M20";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H2:  return "H2";
      case PERIOD_H3:  return "H3";
      case PERIOD_H4:  return "H4";
      case PERIOD_H6:  return "H6";
      case PERIOD_H8:  return "H8";
      case PERIOD_H12: return "H12";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN1";
      default:         return "M15";
   }
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
//| Check if string is in array                                        |
//+------------------------------------------------------------------+
bool IsInArray(string value, string &arr[], int count)
{
   for(int i = 0; i < count; i++)
   {
      if(arr[i] == value)
         return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Manual capture function (can be called from button/hotkey)         |
//+------------------------------------------------------------------+
void ManualCapture()
{
   if(InpGroupedCapture)
      CaptureGroupedSnapshots("manual");
   else
      CaptureCurrentTimeframe("manual");
}
//+------------------------------------------------------------------+
