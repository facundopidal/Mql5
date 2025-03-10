//+------------------------------------------------------------------+
//|                       6-SuperBot3000.mq5                         |
//|                                                                  |
//|                                                                  |
//+------------------------------------------------------------------+

#include <Trade/Trade.mqh>

//Inputs

input group "💹 Indicadores";
input int fast_ema_period = 20;        // Periodo EMA Rápida
input int slow_ema_period = 50;        // Periodo EMA Lenta
input int adx_period = 14;             // Periodo ADX
input int atr_period = 14;             // Periodo ATR
input int cci_period = 35;             // Periodo CCI
input int wpr_period = 14;             // Periodo %R

input group "🥒 Filtros"
input int cci_value = 120;             // Filtro CCI
input int adx_value = 25;              // Filtro ADX
input int wpr_top = -20;               // %R Short
input int wpr_bottom = -80;            // %R Long
input double entry_break = 0;          // Entry Break

input group "⏰ Filtro horario";
input int start_hour = 8;              // Hora de inicio de operaciones
input int trade_duration = 8;          // Cantidad de horas de operacion

input group "💸 Posición";
input int max_spread_pips = 6;         // Spread Máximo en Pips
input double tp_atr = 1.5;             // Take Profit en ATRs
input double sl_atr = 1;               // Stop Loss en ATRs
input double min_lots = 0.1;           // Lotaje Minimo
input double risk = 0.01;              // Riesgo

//Handlers

int cci_h;
int adx_h;
int atr_h;
int wpr_h;
int fast_ema_h;
int slow_ema_h;

double cci[];
double adx[];
double atr[];
double wpr[];
double fast_ema[];
double slow_ema[];

// Variables 

CTrade trade;
ulong trade_ticket = 0;

double lotaje;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
   
   cci_h = iCCI(_Symbol, PERIOD_CURRENT, cci_period, PRICE_CLOSE);
   adx_h = iADX(_Symbol, PERIOD_CURRENT, adx_period);
   atr_h = iATR(_Symbol, PERIOD_CURRENT, atr_period);
   wpr_h = iWPR(_Symbol, PERIOD_CURRENT, wpr_period);
   fast_ema_h = iMA(_Symbol, PERIOD_CURRENT, fast_ema_period, 1, MODE_EMA, PRICE_CLOSE);
   slow_ema_h = iMA(_Symbol, PERIOD_CURRENT, slow_ema_period, 1, MODE_EMA, PRICE_CLOSE);
   
   PlotIndexSetInteger(fast_ema_h, PLOT_LINE_COLOR, 0,clrGreenYellow);
   
   ArraySetAsSeries(cci, true);
   ArraySetAsSeries(adx, true);
   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(fast_ema, true);
   ArraySetAsSeries(slow_ema, true);
   
   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
   
   if(!PositionSelectByTicket(trade_ticket)) {
      trade_ticket = 0;
   }
   
   if(trade_ticket > 0) {
      Print("Ya hay operaciones abiertas");
      return;
   }
   
   CopyBuffer(cci_h, 0, 1, 1, cci);
   CopyBuffer(adx_h, 0, 1, 1, adx);
   CopyBuffer(atr_h, 0, 1, 1, atr);
   CopyBuffer(wpr_h, 0, 1, 1, wpr);
   CopyBuffer(fast_ema_h, 0, 1, 1, fast_ema);
   CopyBuffer(slow_ema_h, 0, 1, 1, slow_ema);
   
   MqlDateTime time = {};
   TimeCurrent(time);
   
//----------------------Filtros--------------------------
   
   if (!DentroHorarioOperacion(time.hour)) {
      Print("Fuera de horario");
      return;
   }  
   
   if(adx[0] <= adx_value) {
      Print("ADX Bajo");
      return;
   }
   
   if(AltoSpread()) {
      Print("Alto Spread");
      return;
   }
   
//----------------------Operaciones--------------------------

   MqlRates rate[];
   
   CopyRates(_Symbol, PERIOD_CURRENT, 1, 1, rate);
   
   if(wpr[0] < wpr_bottom) {
      Print("%R da compra");
   }
   
   if(wpr[0] > wpr_top) {
      Print("%R da venta");
   }

   if(wpr[0] < wpr_bottom && fast_ema[0] > slow_ema[0] && rate[0].low <= fast_ema[0] && rate[0].close > (fast_ema[0] * (1 + entry_break * _Point))) {
      EjecutarCompra();
   } else if(wpr[0] > wpr_top && fast_ema[0] < slow_ema[0] && rate[0].high >= fast_ema[0] && rate[0].close < (fast_ema[0] * (1 - entry_break * _Point))) {
      EjecutarVenta();
   }
}
//+------------------------------------------------------------------+
void EjecutarCompra() {
   double Ask = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
   trade.Buy(NormalizeDouble(CalcularLotes(), 2), _Symbol, Ask, Ask - sl_atr * atr[0], Ask + tp_atr * atr[0] * _Point, "SUPER MEGA LONG");
   trade_ticket = trade.ResultOrder();
}

void EjecutarVenta() {

   double Bid = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
   trade.Sell(NormalizeDouble(CalcularLotes(), 2), _Symbol, Bid, Bid + sl_atr * atr[0], Bid - tp_atr * atr[0], "SUPER MEGA SHORT");
   trade_ticket = trade.ResultOrder();
   
}

double CalcularLotes() {
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double max_risk = equity * risk;
   double atr_stop_loss = sl_atr * atr[0];
   double position_size = 0;
//---------------------------------ESTO ES UNA GRAN MENTIRA-------------------------------------

   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

// Calcular el lotaje permitido: se divide el riesgo máximo (en dinero) entre el riesgo por lote
// y se ajusta dividiendo entre el tamaño del contrato.
   double lotaje_permitido = NormalizeDouble((max_risk / (atr_stop_loss / tick_size)) / tick_value, _Digits);   
   
   lotaje = lotaje_permitido < min_lots ? min_lots : lotaje_permitido;
   
   return lotaje;
}

bool DentroHorarioOperacion(int hora_actual) {
   int hora_fin = start_hour + trade_duration;
   if (hora_fin >= 24) hora_fin -= 24; // Asegura que no pase de las 24 horas

   if (start_hour < hora_fin) {
      return (hora_actual >= start_hour && hora_actual < hora_fin);
   } else {
      // Caso en el que el horario cruza la medianoche
      return (hora_actual >= start_hour || hora_actual < hora_fin);
   }
}

bool AltoSpread() {
   double Ask = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
   double Bid = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
   
   return ((Ask-Bid) / _Point) > max_spread_pips;
}