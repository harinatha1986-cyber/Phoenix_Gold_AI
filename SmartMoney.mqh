//+------------------------------------------------------------------+
//|                                                   SmartMoney.mqh |
//|                                  Copyright 2026, Phoenix Gold AI |
//|                                       https://www.google.com/    |
//|                                                                  |
//| Detects Smart Money Concepts (SMC): Swings, BOS, CHoCH,          |
//| Order Blocks (OB), Fair Value Gaps (FVG), Liquidity Sweeps,      |
//| and Premium/Discount Zones.                                      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Phoenix Gold AI"
#property link      "https://www.google.com/"
#property version   "1.00"
#property once

#include "Utilities.mqh"
#include "Logger.mqh"

//+------------------------------------------------------------------+
//| Class CSmartMoney                                                |
//| Computes SMC price action structures                            |
//+------------------------------------------------------------------+
enum ENUM_BLOCK_TYPE
{
   BLOCK_OB,
   BLOCK_BREAKER,
   BLOCK_MITIGATION
};

class CSmartMoney
{
private:
   // Structure to define order blocks
   struct OrderBlock
   {
      double            top;
      double            bottom;
      bool              is_bullish;
      bool              is_active;
      datetime          time;
      ENUM_BLOCK_TYPE   block_type;
   };

   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   
   double            m_last_swing_high;
   double            m_last_swing_low;
   bool              m_bos_detected;
   bool              m_choch_detected;
   
   OrderBlock        m_order_blocks[];
   int               m_ob_count;

   // Internal detection algorithms
   void              UpdateSwings();
   void              UpdateOrderBlocks();

public:
                     CSmartMoney();
                    ~CSmartMoney() {}
                    
   // Initialize symbol and timeframe
   void              Init(const string symbol, const ENUM_TIMEFRAMES tf);
   
   // Perform full structure scan (call on new bar)
   void              ScanSMC();
   
   // Premium / Discount Zone check
   // Returns: 1 = Premium, 0 = Equilibrium, -1 = Discount
   int               GetPremiumDiscountZone(const double price, const int lookback=100);
   
   // Detect if there is a Fair Value Gap (FVG) at candle index
   bool              DetectFVG(const int index, bool &out_is_bullish, double &out_gap_top, double &out_gap_bottom);
   
   // Detect if a Liquidity Sweep occurred on the last closed bar
   bool              DetectLiquiditySweep(bool &out_is_bullish);
   
   // Getters for structure signals
   bool              IsBOS()                 const { return m_bos_detected; }
   bool              IsCHoCH()               const { return m_choch_detected; }
   double            GetLastSwingHigh()      const { return m_last_swing_high; }
   double            GetLastSwingLow()       const { return m_last_swing_low; }
   
   // Search for active order block zones
   bool              IsPriceInOrderBlock(const double price, const bool bullish_ob, double &out_ob_top, double &out_ob_bottom);
   bool              IsPriceInBreakerBlock(const double price, const bool bullish_breaker, double &out_ob_top, double &out_ob_bottom);
   bool              IsPriceInMitigationBlock(const double price, const bool bullish_mitigation, double &out_ob_top, double &out_ob_bottom);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CSmartMoney::CSmartMoney() : m_symbol(""),
                             m_tf(PERIOD_M15),
                             m_last_swing_high(0.0),
                             m_last_swing_low(0.0),
                             m_bos_detected(false),
                             m_choch_detected(false),
                             m_ob_count(0)
{
   ArrayResize(m_order_blocks, 0);
}

//+------------------------------------------------------------------+
//| Init                                                             |
//+------------------------------------------------------------------+
void CSmartMoney::Init(const string symbol, const ENUM_TIMEFRAMES tf)
{
   m_symbol = symbol;
   m_tf = tf;
   m_last_swing_high = 0.0;
   m_last_swing_low = 0.0;
   m_bos_detected = false;
   m_choch_detected = false;
   m_ob_count = 0;
   ArrayResize(m_order_blocks, 0);
   
   Logger.Info(StringFormat("Smart Money Module initialized for %s on %s", m_symbol, EnumToString(m_tf)));
}

//+------------------------------------------------------------------+
//| ScanSMC                                                          |
//+------------------------------------------------------------------+
void CSmartMoney::ScanSMC()
{
   UpdateSwings();
   UpdateOrderBlocks();
}

//+------------------------------------------------------------------+
//| UpdateSwings                                                     |
//+------------------------------------------------------------------+
void CSmartMoney::UpdateSwings()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(m_symbol, m_tf, 0, 100, rates);
   if(copied < 5) return;
   
   double prev_high = m_last_swing_high;
   double prev_low = m_last_swing_low;
   
   m_bos_detected = false;
   m_choch_detected = false;
   
   // Scan for swing high (Fractal of 5 bars: i is center bar)
   for(int i = 2; i < copied - 2; i++)
   {
      if(rates[i].high > rates[i-1].high && rates[i].high > rates[i-2].high &&
         rates[i].high > rates[i+1].high && rates[i].high > rates[i+2].high)
      {
         m_last_swing_high = rates[i].high;
         break;
      }
   }
   
   // Scan for swing low
   for(int i = 2; i < copied - 2; i++)
   {
      if(rates[i].low < rates[i-1].low && rates[i].low < rates[i-2].low &&
         rates[i].low < rates[i+1].low && rates[i].low < rates[i+2].low)
      {
         m_last_swing_low = rates[i].low;
         break;
      }
   }
   
   // Check for breaks on the most recently closed bar (index 1)
   if(prev_high > 0.0 && prev_low > 0.0)
   {
      if(rates[1].close > prev_high)
      {
         // Price breaks swing high. Check if it's a bullish BOS or CHoCH.
         // If it broke the high after a downward swing, it's a Change of Character (CHoCH)
         if(rates[2].close < prev_low)
         {
            m_choch_detected = true;
         }
         else
         {
            m_bos_detected = true;
         }
      }
      else if(rates[1].close < prev_low)
      {
         // Price breaks swing low.
         if(rates[2].close > prev_high)
         {
            m_choch_detected = true;
         }
         else
         {
            m_bos_detected = true;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| UpdateOrderBlocks                                                |
//+------------------------------------------------------------------+
void CSmartMoney::UpdateOrderBlocks()
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(m_symbol, m_tf, 0, 50, rates);
   if(copied < 5) return;
   
   // 1. Mitigate/Invalidate existing order blocks
   double current_price = rates[0].close;
   for(int i = 0; i < m_ob_count; i++)
   {
      if(!m_order_blocks[i].is_active) continue;
      
      if(m_order_blocks[i].is_bullish)
      {
         // Bullish OB is mitigated if price touches it, and broken if price closes below it
         if(current_price < m_order_blocks[i].bottom)
         {
            if(m_order_blocks[i].block_type == BLOCK_OB)
            {
               bool swept = (m_order_blocks[i].top > m_last_swing_high);
               m_order_blocks[i].block_type = swept ? BLOCK_BREAKER : BLOCK_MITIGATION;
               m_order_blocks[i].is_bullish = false; // Becomes bearish resistance block
               m_order_blocks[i].is_active = true;
            }
            else
            {
               m_order_blocks[i].is_active = false; // Invalidated if already a breaker/mitigation
            }
         }
         else if(rates[1].low <= m_order_blocks[i].top)
         {
            m_order_blocks[i].is_active = false; 
         }
      }
      else
      {
         // Bearish OB
         if(current_price > m_order_blocks[i].top)
         {
            if(m_order_blocks[i].block_type == BLOCK_OB)
            {
               bool swept = (m_order_blocks[i].bottom < m_last_swing_low);
               m_order_blocks[i].block_type = swept ? BLOCK_BREAKER : BLOCK_MITIGATION;
               m_order_blocks[i].is_bullish = true; // Becomes bullish support block
               m_order_blocks[i].is_active = true;
            }
            else
            {
               m_order_blocks[i].is_active = false; // Invalidated if already a breaker/mitigation
            }
         }
         else if(rates[1].high >= m_order_blocks[i].bottom)
         {
            m_order_blocks[i].is_active = false;
         }
      }
   }
   
   // 2. Identify new Order Blocks on the last closed candle (index 1)
   // Bullish OB: Bearish candle (index 2) followed by a strong bullish candle (index 1)
   bool is_bearish_c2 = (rates[2].close < rates[2].open);
   bool is_bullish_c1 = (rates[1].close > rates[1].open);
   
   if(is_bearish_c2 && is_bullish_c1)
   {
      // Strong body expansion (body of c1 is larger than average)
      double body_size = rates[1].close - rates[1].open;
      double range_avg = 0.0;
      for(int k = 1; k < 10; k++) range_avg += (rates[k].high - rates[k].low);
      range_avg /= 9.0;
      
      if(body_size > range_avg * 0.8)
      {
         // Add new Bullish OB (the body/wick area of bearish candle index 2)
         m_ob_count++;
         ArrayResize(m_order_blocks, m_ob_count);
         m_order_blocks[m_ob_count - 1].top = rates[2].high;
         m_order_blocks[m_ob_count - 1].bottom = rates[2].low;
         m_order_blocks[m_ob_count - 1].is_bullish = true;
         m_order_blocks[m_ob_count - 1].is_active = true;
         m_order_blocks[m_ob_count - 1].time = rates[2].time;
         m_order_blocks[m_ob_count - 1].block_type = BLOCK_OB;
      }
   }
   
   // Bearish OB: Bullish candle (index 2) followed by a strong bearish candle (index 1)
   bool is_bullish_c2 = (rates[2].close > rates[2].open);
   bool is_bearish_c1 = (rates[1].close < rates[1].open);
   
   if(is_bullish_c2 && is_bearish_c1)
   {
      double body_size = rates[1].open - rates[1].close;
      double range_avg = 0.0;
      for(int k = 1; k < 10; k++) range_avg += (rates[k].high - rates[k].low);
      range_avg /= 9.0;
      
      if(body_size > range_avg * 0.8)
      {
         // Add new Bearish OB (the body/wick area of bullish candle index 2)
         m_ob_count++;
         ArrayResize(m_order_blocks, m_ob_count);
         m_order_blocks[m_ob_count - 1].top = rates[2].high;
         m_order_blocks[m_ob_count - 1].bottom = rates[2].low;
         m_order_blocks[m_ob_count - 1].is_bullish = false;
         m_order_blocks[m_ob_count - 1].is_active = true;
         m_order_blocks[m_ob_count - 1].time = rates[2].time;
         m_order_blocks[m_ob_count - 1].block_type = BLOCK_OB;
      }
   }
   
   // Keep cache clean (remove inactive ones if the cache grows too large)
   if(m_ob_count > 30)
   {
      OrderBlock temp[];
      int active_cnt = 0;
      for(int i = 0; i < m_ob_count; i++)
      {
         if(m_order_blocks[i].is_active)
         {
            active_cnt++;
            ArrayResize(temp, active_cnt);
            temp[active_cnt - 1] = m_order_blocks[i];
         }
      }
      
      m_ob_count = active_cnt;
      ArrayResize(m_order_blocks, m_ob_count);
      for(int i = 0; i < m_ob_count; i++)
      {
         m_order_blocks[i] = temp[i];
      }
   }
}

//+------------------------------------------------------------------+
//| GetPremiumDiscountZone                                           |
//+------------------------------------------------------------------+
int CSmartMoney::GetPremiumDiscountZone(const double price, const int lookback=100)
{
   double highest_price = -99999.0;
   double lowest_price = 99999.0;
   
   MqlRates rates[];
   int copied = CopyRates(m_symbol, m_tf, 0, lookback, rates);
   if(copied <= 0) return 0; // Equilibrium fallback
   
   for(int i = 0; i < copied; i++)
   {
      if(rates[i].high > highest_price) highest_price = rates[i].high;
      if(rates[i].low < lowest_price)   lowest_price = rates[i].low;
   }
   
   double range = highest_price - lowest_price;
   if(range <= 0.0) return 0;
   
   double eq = lowest_price + (range * 0.5);
   
   // Premium > 50% range, Discount < 50% range
   if(price > eq + (range * 0.02)) return 1;       // Premium
   if(price < eq - (range * 0.02)) return -1;      // Discount
   
   return 0; // Equilibrium Zone
}

//+------------------------------------------------------------------+
//| DetectFVG                                                        |
//+------------------------------------------------------------------+
bool CSmartMoney::DetectFVG(const int index, bool &out_is_bullish, double &out_gap_top, double &out_gap_bottom)
{
   MqlRates rates[];
   // Copy 3 rates starting from index to get rates[index], rates[index+1], rates[index+2]
   int copied = CopyRates(m_symbol, m_tf, index, 3, rates);
   if(copied < 3) return false;
   
   // Since copied rates are returned in chronological order:
   // rates[0] is index+2 (oldest), rates[1] is index+1 (middle), rates[2] is index (newest)
   double high_oldest = rates[0].high;
   double low_newest  = rates[2].low;
   
   // Bullish FVG: Low of newest candle is higher than High of oldest candle
   if(low_newest > high_oldest)
   {
      out_is_bullish = true;
      out_gap_bottom = high_oldest;
      out_gap_top    = low_newest;
      return true;
   }
   
   double low_oldest  = rates[0].low;
   double high_newest = rates[2].high;
   
   // Bearish FVG: High of newest candle is lower than Low of oldest candle
   if(high_newest < low_oldest)
   {
      out_is_bullish = false;
      out_gap_bottom = high_newest;
      out_gap_top    = low_oldest;
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| DetectLiquiditySweep                                             |
//+------------------------------------------------------------------+
bool CSmartMoney::DetectLiquiditySweep(bool &out_is_bullish)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(m_symbol, m_tf, 0, 5, rates);
   if(copied < 5) return false;
   
   // The sweep occurred on the last closed candle (index 1) relative to recent swings
   if(m_last_swing_high > 0.0 && rates[1].high > m_last_swing_high && rates[1].close < m_last_swing_high)
   {
      out_is_bullish = false; // Bearish sweep (swept buy stops at swing high and closed back down)
      return true;
   }
   
   if(m_last_swing_low > 0.0 && rates[1].low < m_last_swing_low && rates[1].close > m_last_swing_low)
   {
      out_is_bullish = true;  // Bullish sweep (swept sell stops at swing low and closed back up)
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| IsPriceInOrderBlock                                              |
//+------------------------------------------------------------------+
bool CSmartMoney::IsPriceInOrderBlock(const double price, const bool bullish_ob, double &out_ob_top, double &out_ob_bottom)
{
   for(int i = 0; i < m_ob_count; i++)
   {
      if(!m_order_blocks[i].is_active || m_order_blocks[i].block_type != BLOCK_OB) continue;
      
      if(m_order_blocks[i].is_bullish == bullish_ob)
      {
         if(price >= m_order_blocks[i].bottom && price <= m_order_blocks[i].top)
         {
            out_ob_top = m_order_blocks[i].top;
            out_ob_bottom = m_order_blocks[i].bottom;
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| IsPriceInBreakerBlock                                            |
//+------------------------------------------------------------------+
bool CSmartMoney::IsPriceInBreakerBlock(const double price, const bool bullish_breaker, double &out_ob_top, double &out_ob_bottom)
{
   for(int i = 0; i < m_ob_count; i++)
   {
      if(!m_order_blocks[i].is_active || m_order_blocks[i].block_type != BLOCK_BREAKER) continue;
      
      if(m_order_blocks[i].is_bullish == bullish_breaker)
      {
         if(price >= m_order_blocks[i].bottom && price <= m_order_blocks[i].top)
         {
            out_ob_top = m_order_blocks[i].top;
            out_ob_bottom = m_order_blocks[i].bottom;
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| IsPriceInMitigationBlock                                         |
//+------------------------------------------------------------------+
bool CSmartMoney::IsPriceInMitigationBlock(const double price, const bool bullish_mitigation, double &out_ob_top, double &out_ob_bottom)
{
   for(int i = 0; i < m_ob_count; i++)
   {
      if(!m_order_blocks[i].is_active || m_order_blocks[i].block_type != BLOCK_MITIGATION) continue;
      
      if(m_order_blocks[i].is_bullish == bullish_mitigation)
      {
         if(price >= m_order_blocks[i].bottom && price <= m_order_blocks[i].top)
         {
            out_ob_top = m_order_blocks[i].top;
            out_ob_bottom = m_order_blocks[i].bottom;
            return true;
         }
      }
   }
   return false;
}
