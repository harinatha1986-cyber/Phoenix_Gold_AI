//+------------------------------------------------------------------+
//|                                             IndicatorManager.mqh |
//|                                  Copyright 2026, Phoenix Gold AI |
//|                                       https://www.google.com/    |
//|                                                                  |
//| Manages MT5 indicator handles, memory allocation, and optimizes  |
//| data copying with double caching to prevent latency on tick updates.|
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Phoenix Gold AI"
#property link      "https://www.google.com/"
#property version   "1.00"
#property once

#include "Utilities.mqh"
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| Class CIndicatorManager                                          |
//| Safe wrapper for technical indicators and series data access     |
//+------------------------------------------------------------------+
class CIndicatorManager
{
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_pri_tf;
   ENUM_TIMEFRAMES   m_trend_tf;
   
   // Handles
   int               m_h_ema20_pri;
   int               m_h_ema50_pri;
   int               m_h_ema200_pri;
   int               m_h_rsi_pri;
   int               m_h_atr_pri;
   
   int               m_h_ema20_trend;
   int               m_h_ema50_trend;
   int               m_h_ema200_trend;
   
   // Cached buffers (arranged as series, i.e., index 0 = current bar)
   double            m_ema20_pri_buf[];
   double            m_ema50_pri_buf[];
   double            m_ema200_pri_buf[];
   double            m_rsi_pri_buf[];
   double            m_atr_pri_buf[];
   
   double            m_ema20_trend_buf[];
   double            m_ema50_trend_buf[];
   double            m_ema200_trend_buf[];
   
   long              m_volume_buf[];
   double            m_close_pri_buf[];
   
   // Safe handle release helper
   void              ReleaseHandle(int &handle);

public:
                     CIndicatorManager();
                    ~CIndicatorManager();
                    
   // Initialize all indicator handles
   bool              Init(const string symbol, const ENUM_TIMEFRAMES pri_tf, const ENUM_TIMEFRAMES trend_tf);
   
   // Reconstruct indicators and clean memory
   void              Release();
   
   // Fetch latest data into buffers (returns true if successful)
   bool              UpdateData();
   
   // Data Accessors (Primary Timeframe)
   double            GetEMA20_Pri(const int index)    const { return m_ema20_pri_buf[index]; }
   double            GetEMA50_Pri(const int index)    const { return m_ema50_pri_buf[index]; }
   double            GetEMA200_Pri(const int index)   const { return m_ema200_pri_buf[index]; }
   double            GetRSI_Pri(const int index)      const { return m_rsi_pri_buf[index]; }
   double            GetATR_Pri(const int index)      const { return m_atr_pri_buf[index]; }
   double            GetClose_Pri(const int index)    const { return m_close_pri_buf[index]; }
   long              GetVolume_Pri(const int index)   const { return m_volume_buf[index]; }
   
   // Data Accessors (Trend Confirmation Timeframe)
   double            GetEMA20_Trend(const int index)  const { return m_ema20_trend_buf[index]; }
   double            GetEMA50_Trend(const int index)  const { return m_ema50_trend_buf[index]; }
   double            GetEMA200_Trend(const int index) const { return m_ema200_trend_buf[index]; }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CIndicatorManager::CIndicatorManager() : m_symbol(""),
                                         m_pri_tf(PERIOD_M15),
                                         m_trend_tf(PERIOD_H1),
                                         m_h_ema20_pri(INVALID_HANDLE),
                                         m_h_ema50_pri(INVALID_HANDLE),
                                         m_h_ema200_pri(INVALID_HANDLE),
                                         m_h_rsi_pri(INVALID_HANDLE),
                                         m_h_atr_pri(INVALID_HANDLE),
                                         m_h_ema20_trend(INVALID_HANDLE),
                                         m_h_ema50_trend(INVALID_HANDLE),
                                         m_h_ema200_trend(INVALID_HANDLE)
{
   // Set all caching arrays as timeseries
   ArraySetAsSeries(m_ema20_pri_buf, true);
   ArraySetAsSeries(m_ema50_pri_buf, true);
   ArraySetAsSeries(m_ema200_pri_buf, true);
   ArraySetAsSeries(m_rsi_pri_buf, true);
   ArraySetAsSeries(m_atr_pri_buf, true);
   
   ArraySetAsSeries(m_ema20_trend_buf, true);
   ArraySetAsSeries(m_ema50_trend_buf, true);
   ArraySetAsSeries(m_ema200_trend_buf, true);
   
   ArraySetAsSeries(m_volume_buf, true);
   ArraySetAsSeries(m_close_pri_buf, true);
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CIndicatorManager::~CIndicatorManager()
{
   Release();
}

//+------------------------------------------------------------------+
//| ReleaseHandle                                                    |
//+------------------------------------------------------------------+
void CIndicatorManager::ReleaseHandle(int &handle)
{
   if(handle != INVALID_HANDLE)
   {
      IndicatorRelease(handle);
      handle = INVALID_HANDLE;
   }
}

//+------------------------------------------------------------------+
//| Release                                                          |
//+------------------------------------------------------------------+
void CIndicatorManager::Release()
{
   ReleaseHandle(m_h_ema20_pri);
   ReleaseHandle(m_h_ema50_pri);
   ReleaseHandle(m_h_ema200_pri);
   ReleaseHandle(m_h_rsi_pri);
   ReleaseHandle(m_h_atr_pri);
   
   ReleaseHandle(m_h_ema20_trend);
   ReleaseHandle(m_h_ema50_trend);
   ReleaseHandle(m_h_ema200_trend);
   
   Logger.Info("All indicator handles released.");
}

//+------------------------------------------------------------------+
//| Init                                                             |
//+------------------------------------------------------------------+
bool CIndicatorManager::Init(const string symbol, const ENUM_TIMEFRAMES pri_tf, const ENUM_TIMEFRAMES trend_tf)
{
   m_symbol = symbol;
   m_pri_tf = pri_tf;
   m_trend_tf = trend_tf;
   
   // Clean any existing handles first
   Release();
   
   // 1. Primary Timeframe Indicators
   m_h_ema20_pri = iMA(m_symbol, m_pri_tf, 20, 0, MODE_EMA, PRICE_CLOSE);
   m_h_ema50_pri = iMA(m_symbol, m_pri_tf, 50, 0, MODE_EMA, PRICE_CLOSE);
   m_h_ema200_pri = iMA(m_symbol, m_pri_tf, 200, 0, MODE_EMA, PRICE_CLOSE);
   m_h_rsi_pri = iRSI(m_symbol, m_pri_tf, 14, PRICE_CLOSE);
   m_h_atr_pri = iATR(m_symbol, m_pri_tf, 14);
   
   // 2. Trend Confirmation Timeframe Indicators
   m_h_ema20_trend = iMA(m_symbol, m_trend_tf, 20, 0, MODE_EMA, PRICE_CLOSE);
   m_h_ema50_trend = iMA(m_symbol, m_trend_tf, 50, 0, MODE_EMA, PRICE_CLOSE);
   m_h_ema200_trend = iMA(m_symbol, m_trend_tf, 200, 0, MODE_EMA, PRICE_CLOSE);
   
   // Validate handles
   if(m_h_ema20_pri == INVALID_HANDLE || m_h_ema50_pri == INVALID_HANDLE || m_h_ema200_pri == INVALID_HANDLE ||
      m_h_rsi_pri == INVALID_HANDLE || m_h_atr_pri == INVALID_HANDLE ||
      m_h_ema20_trend == INVALID_HANDLE || m_h_ema50_trend == INVALID_HANDLE || m_h_ema200_trend == INVALID_HANDLE)
   {
      Logger.Error("Indicator initialization failed! One or more handles are invalid.");
      Release();
      return false;
   }
   
   Logger.Info(StringFormat("Indicator Manager initialized successfully for %s on Primary: %s, Trend: %s",
      m_symbol, EnumToString(m_pri_tf), EnumToString(m_trend_tf)));
      
   return true;
}

//+------------------------------------------------------------------+
//| UpdateData                                                       |
//+------------------------------------------------------------------+
bool CIndicatorManager::UpdateData()
{
   // Copy last 5 elements to ensure we have enough lookback
   int count = 5;
   
   // Temporary holder arrays for raw CopyBuffer operations
   double temp_ema20_pri[], temp_ema50_pri[], temp_ema200_pri[];
   double temp_rsi_pri[], temp_atr_pri[];
   double temp_ema20_trend[], temp_ema50_trend[], temp_ema200_trend[];
   long temp_vol[];
   double temp_close[];
   
   // Fetch Primary TF
   if(CopyBuffer(m_h_ema20_pri, 0, 0, count, temp_ema20_pri) != count) return false;
   if(CopyBuffer(m_h_ema50_pri, 0, 0, count, temp_ema50_pri) != count) return false;
   if(CopyBuffer(m_h_ema200_pri, 0, 0, count, temp_ema200_pri) != count) return false;
   if(CopyBuffer(m_h_rsi_pri, 0, 0, count, temp_rsi_pri) != count) return false;
   if(CopyBuffer(m_h_atr_pri, 0, 0, count, temp_atr_pri) != count) return false;
   
   // Fetch Trend TF
   if(CopyBuffer(m_h_ema20_trend, 0, 0, count, temp_ema20_trend) != count) return false;
   if(CopyBuffer(m_h_ema50_trend, 0, 0, count, temp_ema50_trend) != count) return false;
   if(CopyBuffer(m_h_ema200_trend, 0, 0, count, temp_ema200_trend) != count) return false;
   
   // Fetch Tick Volume and Close prices
   if(CopyTickVolume(m_symbol, m_pri_tf, 0, count, temp_vol) != count) return false;
   if(CopyClose(m_symbol, m_pri_tf, 0, count, temp_close) != count) return false;
   
   // Copy arrays into class members (ArraySetAsSeries will reverse order correctly)
   // In MQL5, assigning a standard array to a dynamic array copies the values.
   // To keep the series order correct:
   ArrayResize(m_ema20_pri_buf, count);
   ArrayResize(m_ema50_pri_buf, count);
   ArrayResize(m_ema200_pri_buf, count);
   ArrayResize(m_rsi_pri_buf, count);
   ArrayResize(m_atr_pri_buf, count);
   ArrayResize(m_ema20_trend_buf, count);
   ArrayResize(m_ema50_trend_buf, count);
   ArrayResize(m_ema200_trend_buf, count);
   ArrayResize(m_volume_buf, count);
   ArrayResize(m_close_pri_buf, count);
   
   for(int i = 0; i < count; i++)
   {
      // Since temp arrays are 0-indexed from oldest to newest:
      // index 'count - 1 - i' corresponds to index 'i' in series
      m_ema20_pri_buf[i]    = temp_ema20_pri[count - 1 - i];
      m_ema50_pri_buf[i]    = temp_ema50_pri[count - 1 - i];
      m_ema200_pri_buf[i]   = temp_ema200_pri[count - 1 - i];
      m_rsi_pri_buf[i]      = temp_rsi_pri[count - 1 - i];
      m_atr_pri_buf[i]      = temp_atr_pri[count - 1 - i];
      
      m_ema20_trend_buf[i]  = temp_ema20_trend[count - 1 - i];
      m_ema50_trend_buf[i]  = temp_ema50_trend[count - 1 - i];
      m_ema200_trend_buf[i] = temp_ema200_trend[count - 1 - i];
      
      m_volume_buf[i]       = temp_vol[count - 1 - i];
      m_close_pri_buf[i]    = temp_close[count - 1 - i];
   }
   
   return true;
}
