//+------------------------------------------------------------------+
//|                                                SessionFilter.mqh |
//|                                  Copyright 2026, Phoenix Gold AI |
//|                                       https://www.google.com/    |
//|                                                                  |
//| Handles trading session boundaries (Asian, London, New York)     |
//| and institutional Kill Zones.                                    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Phoenix Gold AI"
#property link      "https://www.google.com/"
#property version   "1.00"
#property once

#include "Utilities.mqh"
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| Class CSessionFilter                                             |
//| Manages session checks and trading hour filters                  |
//+------------------------------------------------------------------+
class CSessionFilter
{
private:
   int            m_asia_start;
   int            m_asia_end;
   int            m_london_start;
   int            m_london_end;
   int            m_ny_start;
   int            m_ny_end;
   int            m_sydney_start;
   int            m_sydney_end;
   
   int            m_tokyo_kill_start;
   int            m_tokyo_kill_end;
   int            m_london_kill_start;
   int            m_london_kill_end;
   int            m_ny_kill_start;
   int            m_ny_kill_end;

   // Internal range checker that handles midnight crossings
   bool           IsTimeInRange(const int time_mins, const int start_mins, const int end_mins);

public:
                  CSessionFilter();
                 ~CSessionFilter() {}

    // Dynamic configuration methods
   void           SetSessions(const string asia_start, const string asia_end,
                              const string london_start, const string london_end,
                              const string ny_start, const string ny_end,
                              const string sydney_start, const string sydney_end);
                              
   void           SetKillZones(const string tokyo_start, const string tokyo_end,
                               const string london_start, const string london_end,
                               const string ny_start, const string ny_end);

   // Status check methods
   bool           IsAsianSessionActive(const datetime time);
   bool           IsLondonSessionActive(const datetime time);
   bool           IsNewYorkSessionActive(const datetime time);
   bool           IsSydneySessionActive(const datetime time);
   bool           IsAnySessionActive(const datetime time);
   bool           IsLondonNYOverlapActive(const datetime time);
   
   bool           IsTokyoKillZone(const datetime time);
   bool           IsLondonKillZone(const datetime time);
   bool           IsNewYorkKillZone(const datetime time);
   bool           IsAnyKillZoneActive(const datetime time);
};

//+------------------------------------------------------------------+
//| Constructor - Initializes default session times in Broker Time   |
//+------------------------------------------------------------------+
CSessionFilter::CSessionFilter()
{
   // Default times assume GMT+2/3 Broker Server Time
   // Asian: 00:00 - 08:00
   m_asia_start = 0;
   m_asia_end = 480;
   
   // London: 09:00 - 18:00
   m_london_start = 540;
   m_london_end = 1080;
   
   // New York: 15:00 - 24:00
   m_ny_start = 900;
   m_ny_end = 1439;
   
   // Sydney: 23:00 - 07:00
   m_sydney_start = 1380;
   m_sydney_end = 420;
   
   // Tokyo Open Kill Zone: 01:00 - 03:00
   m_tokyo_kill_start = 60;
   m_tokyo_kill_end = 180;
   
   // London Open Kill Zone: 08:00 - 10:00
   m_london_kill_start = 480;
   m_london_kill_end = 600;
   
   // NY Open Kill Zone: 14:00 - 16:00
   m_ny_kill_start = 840;
   m_ny_kill_end = 960;
}

//+------------------------------------------------------------------+
//| SetSessions                                                      |
//+------------------------------------------------------------------+
void CSessionFilter::SetSessions(const string asia_start, const string asia_end,
                                 const string london_start, const string london_end,
                                 const string ny_start, const string ny_end,
                                 const string sydney_start, const string sydney_end)
{
   int a_start = CUtilities::StringToMinutes(asia_start);
   int a_end = CUtilities::StringToMinutes(asia_end);
   int l_start = CUtilities::StringToMinutes(london_start);
   int l_end = CUtilities::StringToMinutes(london_end);
   int n_start = CUtilities::StringToMinutes(ny_start);
   int n_end = CUtilities::StringToMinutes(ny_end);
   int s_start = CUtilities::StringToMinutes(sydney_start);
   int s_end = CUtilities::StringToMinutes(sydney_end);
   
   if(a_start != -1 && a_end != -1) { m_asia_start = a_start; m_asia_end = a_end; }
   if(l_start != -1 && l_end != -1) { m_london_start = l_start; m_london_end = l_end; }
   if(n_start != -1 && n_end != -1) { m_ny_start = n_start; m_ny_end = n_end; }
   if(s_start != -1 && s_end != -1) { m_sydney_start = s_start; m_sydney_end = s_end; }
   
   Logger.Info(StringFormat("Sessions updated: Asia[%s-%s], London[%s-%s], NY[%s-%s], Sydney[%s-%s]", 
      asia_start, asia_end, london_start, london_end, ny_start, ny_end, sydney_start, sydney_end));
}

//+------------------------------------------------------------------+
//| SetKillZones                                                     |
//+------------------------------------------------------------------+
void CSessionFilter::SetKillZones(const string tokyo_start, const string tokyo_end,
                                  const string london_start, const string london_end,
                                  const string ny_start, const string ny_end)
{
   int t_start = CUtilities::StringToMinutes(tokyo_start);
   int t_end = CUtilities::StringToMinutes(tokyo_end);
   int l_start = CUtilities::StringToMinutes(london_start);
   int l_end = CUtilities::StringToMinutes(london_end);
   int n_start = CUtilities::StringToMinutes(ny_start);
   int n_end = CUtilities::StringToMinutes(ny_end);
   
   if(t_start != -1 && t_end != -1) { m_tokyo_kill_start = t_start; m_tokyo_kill_end = t_end; }
   if(l_start != -1 && l_end != -1) { m_london_kill_start = l_start; m_london_kill_end = l_end; }
   if(n_start != -1 && n_end != -1) { m_ny_kill_start = n_start; m_ny_kill_end = n_end; }
   
   Logger.Info(StringFormat("Kill Zones updated: Tokyo[%s-%s], London[%s-%s], NY[%s-%s]", 
      tokyo_start, tokyo_end, london_start, london_end, ny_start, ny_end));
}

//+------------------------------------------------------------------+
//| IsTimeInRange                                                    |
//+------------------------------------------------------------------+
bool CSessionFilter::IsTimeInRange(const int time_mins, const int start_mins, const int end_mins)
{
   if(start_mins <= end_mins)
   {
      return (time_mins >= start_mins && time_mins <= end_mins);
   }
   // Midnight crossing case (e.g. 22:00 to 04:00)
   return (time_mins >= start_mins || time_mins <= end_mins);
}

//+------------------------------------------------------------------+
//| IsAsianSessionActive                                             |
//+------------------------------------------------------------------+
bool CSessionFilter::IsAsianSessionActive(const datetime time)
{
   if(CUtilities::IsWeekend(time)) return false;
   return IsTimeInRange(CUtilities::TimeToMinutes(time), m_asia_start, m_asia_end);
}

//+------------------------------------------------------------------+
//| IsLondonSessionActive                                            |
//+------------------------------------------------------------------+
bool CSessionFilter::IsLondonSessionActive(const datetime time)
{
   if(CUtilities::IsWeekend(time)) return false;
   return IsTimeInRange(CUtilities::TimeToMinutes(time), m_london_start, m_london_end);
}

//+------------------------------------------------------------------+
//| IsNewYorkSessionActive                                           |
//+------------------------------------------------------------------+
bool CSessionFilter::IsNewYorkSessionActive(const datetime time)
{
   if(CUtilities::IsWeekend(time)) return false;
   return IsTimeInRange(CUtilities::TimeToMinutes(time), m_ny_start, m_ny_end);
}

//+------------------------------------------------------------------+
//| IsAnySessionActive                                               |
//+------------------------------------------------------------------+
bool CSessionFilter::IsSydneySessionActive(const datetime time)
{
   if(CUtilities::IsWeekend(time)) return false;
   return IsTimeInRange(CUtilities::TimeToMinutes(time), m_sydney_start, m_sydney_end);
}

//+------------------------------------------------------------------+
//| IsAnySessionActive                                               |
//+------------------------------------------------------------------+
bool CSessionFilter::IsAnySessionActive(const datetime time)
{
   return (IsAsianSessionActive(time) || IsLondonSessionActive(time) || IsNewYorkSessionActive(time) || IsSydneySessionActive(time));
}

//+------------------------------------------------------------------+
//| IsLondonNYOverlapActive                                          |
//+------------------------------------------------------------------+
bool CSessionFilter::IsLondonNYOverlapActive(const datetime time)
{
   return (IsLondonSessionActive(time) && IsNewYorkSessionActive(time));
}

//+------------------------------------------------------------------+
//| IsTokyoKillZone                                                  |
//+------------------------------------------------------------------+
bool CSessionFilter::IsTokyoKillZone(const datetime time)
{
   if(CUtilities::IsWeekend(time)) return false;
   return IsTimeInRange(CUtilities::TimeToMinutes(time), m_tokyo_kill_start, m_tokyo_kill_end);
}

//+------------------------------------------------------------------+
//| IsLondonKillZone                                                 |
//+------------------------------------------------------------------+
bool CSessionFilter::IsLondonKillZone(const datetime time)
{
   if(CUtilities::IsWeekend(time)) return false;
   return IsTimeInRange(CUtilities::TimeToMinutes(time), m_london_kill_start, m_london_kill_end);
}

//+------------------------------------------------------------------+
//| IsNewYorkKillZone                                                |
//+------------------------------------------------------------------+
bool CSessionFilter::IsNewYorkKillZone(const datetime time)
{
   if(CUtilities::IsWeekend(time)) return false;
   return IsTimeInRange(CUtilities::TimeToMinutes(time), m_ny_kill_start, m_ny_kill_end);
}

//+------------------------------------------------------------------+
//| IsAnyKillZoneActive                                              |
//+------------------------------------------------------------------+
bool CSessionFilter::IsAnyKillZoneActive(const datetime time)
{
   return (IsTokyoKillZone(time) || IsLondonKillZone(time) || IsNewYorkKillZone(time));
}
