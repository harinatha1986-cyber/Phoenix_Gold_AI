//+------------------------------------------------------------------+
//|                                                   NewsFilter.mqh |
//|                                  Copyright 2026, Phoenix Gold AI |
//|                                       https://www.google.com/    |
//|                                                                  |
//| Built-in MT5 Economic Calendar based news filter to pause        |
//| trading around high-impact USD events.                           |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Phoenix Gold AI"
#property link      "https://www.google.com/"
#property version   "1.00"
#property once

#include "Utilities.mqh"
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| Class CNewsFilter                                                |
//| Pulls economic calendar events and determines trading pauses    |
//+------------------------------------------------------------------+
class CNewsFilter
{
private:
   // Structure to cache important news events
   struct CachedNews
   {
      datetime                      time;
      string                        name;
      ENUM_CALENDAR_EVENT_IMPORTANCE importance;
   };
   
   datetime       m_last_update;       // Last time calendar was updated
   int            m_update_interval;   // Cache duration in seconds (e.g. 1 hour)
   CachedNews     m_news_cache[];      // Array of cached events
   int            m_cache_count;       // Count of events in cache
   
   // Roadmap enhancements
   bool           m_filter_medium_impact;
   bool           m_filter_keywords;
   
   // Pull news events from MT5 economic calendar
   void           FetchCalendarNews();

public:
                  CNewsFilter();
                 ~CNewsFilter() {}
                 
   // Configure news filter
   void           Configure(const bool filter_medium, const bool filter_keywords);
                 
   // Checks if current time is within a news pause window
   bool           IsTradingPaused(const datetime current_time, 
                                  const int mins_before, 
                                  const int mins_after, 
                                  string &out_news_name, 
                                  datetime &out_news_time);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CNewsFilter::CNewsFilter() : m_last_update(0),
                             m_update_interval(3600), // Cache for 1 hour
                             m_cache_count(0),
                             m_filter_medium_impact(false),
                             m_filter_keywords(false)
{
   ArrayResize(m_news_cache, 0);
}

//+------------------------------------------------------------------+
//| Configure                                                        |
//+------------------------------------------------------------------+
void CNewsFilter::Configure(const bool filter_medium, const bool filter_keywords)
{
   m_filter_medium_impact = filter_medium;
   m_filter_keywords = filter_keywords;
   // Clear cache to force refresh on next check
   m_last_update = 0;
   
   Logger.Info(StringFormat("News Filter configured: MediumImpact=%d, KeywordFiltering=%d", 
      m_filter_medium_impact, m_filter_keywords));
}

//+------------------------------------------------------------------+
//| FetchCalendarNews                                                |
//+------------------------------------------------------------------+
void CNewsFilter::FetchCalendarNews()
{
   datetime now = TimeCurrent();
   
   // Only update cache if interval has passed or cache is empty
   if(m_last_update != 0 && (now - m_last_update < m_update_interval))
   {
      return;
   }
   
   // Reset cache count
   m_cache_count = 0;
   ArrayResize(m_news_cache, 0);
   
   // Set range: 12 hours ago to 24 hours in the future
   datetime from_date = now - (12 * 3600);
   datetime to_date = now + (24 * 3600);
   
   MqlCalendarValue values[];
   int values_count = CalendarValueHistory(values, from_date, to_date);
   
   if(values_count <= 0)
   {
      m_last_update = now;
      // If backtesting or calendar is not connected, this could return 0. Log once.
      static bool warned = false;
      if(!warned)
      {
         Logger.Warning("Economic Calendar returned 0 events. Ensure WebRequest is allowed and calendar is active.");
         warned = true;
      }
      return;
   }
   
   for(int i = 0; i < values_count; i++)
   {
      MqlCalendarEvent event;
      if(!CalendarEventById(values[i].event_id, event))
      {
         continue;
      }
      
      // Filter for importance
      bool passes_importance = (event.importance == CALENDAR_IMPORTANCE_HIGH);
      if(m_filter_medium_impact && event.importance == CALENDAR_IMPORTANCE_MEDIUM)
      {
         passes_importance = true;
      }
      
      if(!passes_importance)
      {
         continue;
      }
      
      MqlCalendarCountry country;
      if(!CalendarCountryById(event.country_id, country))
      {
         continue;
      }
      
      // Filter for USD events (major driver for XAUUSD)
      if(country.currency == "USD")
      {
         // Optional keyword checks for NFP, FOMC, CPI, PPI, Interest Rate
         if(m_filter_keywords)
         {
            string name_upper = event.name;
            StringToUpper(name_upper);
            
            bool contains_keyword = (StringFind(name_upper, "FOMC") >= 0 ||
                                     StringFind(name_upper, "NFP") >= 0 ||
                                     StringFind(name_upper, "NON-FARM") >= 0 ||
                                     StringFind(name_upper, "CPI") >= 0 ||
                                     StringFind(name_upper, "PPI") >= 0 ||
                                     StringFind(name_upper, "INTEREST RATE") >= 0 ||
                                     StringFind(name_upper, "FED RATE") >= 0 ||
                                     StringFind(name_upper, "DECISION") >= 0 ||
                                     StringFind(name_upper, "EMPLOYMENT SITUATION") >= 0);
            if(!contains_keyword)
            {
               continue;
            }
         }
         
         // Add to cache
         m_cache_count++;
         ArrayResize(m_news_cache, m_cache_count);
         m_news_cache[m_cache_count - 1].time = values[i].time;
         m_news_cache[m_cache_count - 1].name = event.name;
         m_news_cache[m_cache_count - 1].importance = event.importance;
      }
   }
   
   m_last_update = now;
   Logger.Info(StringFormat("Economic Calendar cache updated. Cached %d high-impact USD events.", m_cache_count));
}

//+------------------------------------------------------------------+
//| IsTradingPaused                                                  |
//+------------------------------------------------------------------+
bool CNewsFilter::IsTradingPaused(const datetime current_time, 
                                  const int mins_before, 
                                  const int mins_after, 
                                  string &out_news_name, 
                                  datetime &out_news_time)
{
   // Ensure cache is updated
   FetchCalendarNews();
   
   if(m_cache_count <= 0)
   {
      return false;
   }
   
   for(int i = 0; i < m_cache_count; i++)
   {
      long time_diff = (long)current_time - (long)m_news_cache[i].time; // in seconds
      
      // time_diff < 0 means news is in the future
      // time_diff > 0 means news has passed
      long before_sec = (long)mins_before * 60;
      long after_sec = (long)mins_after * 60;
      
      if(time_diff >= -before_sec && time_diff <= after_sec)
      {
         out_news_name = m_news_cache[i].name;
         out_news_time = m_news_cache[i].time;
         return true; // We are in the news pause window
      }
   }
   
   return false;
}
