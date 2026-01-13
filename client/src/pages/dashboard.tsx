import { Layout } from "@/components/layout";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { EquityChart } from "@/components/equity-chart";
import { MOCK_STATS, MOCK_TRADES } from "@/lib/mock-data";
import { ArrowUpRight, ArrowDownRight, TrendingUp, Activity, DollarSign, BarChart3, Sparkles } from "lucide-react";
import { cn } from "@/lib/utils";

export default function Dashboard() {
  const stats = [
    {
      label: "Net Profit",
      value: `+$${MOCK_STATS.equityCurve[MOCK_STATS.equityCurve.length - 1].equity - 10000}`,
      subtext: "+10.93% this month",
      icon: DollarSign,
      trend: "up"
    },
    {
      label: "Win Rate",
      value: `${MOCK_STATS.winRate}%`,
      subtext: "Last 20 trades",
      icon: Activity,
      trend: "neutral"
    },
    {
      label: "Profit Factor",
      value: MOCK_STATS.profitFactor,
      subtext: "Gross Profit / Gross Loss",
      icon: TrendingUp,
      trend: "up"
    },
    {
      label: "Avg R-Multiple",
      value: `${MOCK_STATS.avgR}R`,
      subtext: "Risk Reward Ratio",
      icon: BarChart3,
      trend: "up"
    }
  ];

  return (
    <Layout>
      <div className="p-8 space-y-8 max-w-[1600px] mx-auto">
        <div className="flex flex-col gap-2">
          <h1 className="text-3xl font-bold tracking-tight">Dashboard</h1>
          <p className="text-muted-foreground">Welcome back, John. Here's your trading performance overview.</p>
        </div>

        {/* Top Stats Grid */}
        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
          {stats.map((stat, i) => (
            <Card key={i} className="bg-card border-border shadow-sm hover:border-primary/50 transition-colors">
              <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                <CardTitle className="text-sm font-medium text-muted-foreground uppercase tracking-wider">
                  {stat.label}
                </CardTitle>
                <stat.icon className="h-4 w-4 text-muted-foreground" />
              </CardHeader>
              <CardContent>
                <div className="text-2xl font-bold font-mono tracking-tight">{stat.value}</div>
                <p className="text-xs text-muted-foreground mt-1">{stat.subtext}</p>
              </CardContent>
            </Card>
          ))}
        </div>

        {/* Main Chart Section */}
        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4 h-[400px]">
          <EquityChart />
          
          <Card className="col-span-4 lg:col-span-1 h-full flex flex-col">
            <CardHeader>
              <CardTitle className="text-sm font-medium text-muted-foreground uppercase tracking-wider">Recent Activity</CardTitle>
            </CardHeader>
            <CardContent className="flex-1 overflow-auto pr-2">
              <div className="space-y-4">
                {MOCK_TRADES.slice(0, 5).map(trade => (
                  <div key={trade.id} className="flex items-center justify-between text-sm group cursor-pointer hover:bg-accent/50 p-2 rounded-md -mx-2 transition-colors">
                    <div className="flex items-center gap-3">
                      <div className={cn(
                        "w-2 h-2 rounded-full",
                        trade.netPnl > 0 ? "bg-profit" : "bg-loss"
                      )} />
                      <div className="flex flex-col">
                        <span className="font-bold font-mono">{trade.symbol}</span>
                        <span className="text-xs text-muted-foreground capitalize">{trade.side.toLowerCase()} • {trade.volume} lot</span>
                      </div>
                    </div>
                    <div className={cn(
                      "font-mono font-medium",
                      trade.netPnl > 0 ? "text-profit" : "text-loss"
                    )}>
                      {trade.netPnl > 0 ? "+" : ""}{trade.netPnl}
                    </div>
                  </div>
                ))}
              </div>
            </CardContent>
          </Card>
        </div>

        {/* AI Insight Section */}
        <Card className="bg-gradient-to-br from-sidebar to-card border-border">
          <CardHeader>
            <div className="flex items-center gap-2">
              <Sparkles className="w-5 h-5 text-primary" />
              <CardTitle>Weekly AI Insight</CardTitle>
            </div>
          </CardHeader>
          <CardContent>
            <div className="grid md:grid-cols-3 gap-6">
              <div className="space-y-2">
                <h4 className="text-sm font-semibold text-muted-foreground uppercase tracking-wider">Top Strength</h4>
                <p className="text-sm">You are executing trend continuations on <span className="text-foreground font-mono font-bold">EURUSD</span> with high accuracy (85%).</p>
              </div>
              <div className="space-y-2">
                <h4 className="text-sm font-semibold text-muted-foreground uppercase tracking-wider">Main Leak</h4>
                <p className="text-sm">Counter-trend trades during the Asian session are accounting for <span className="text-destructive font-bold">60%</span> of your losses.</p>
              </div>
              <div className="space-y-2">
                <h4 className="text-sm font-semibold text-muted-foreground uppercase tracking-wider">Action Item</h4>
                <p className="text-sm">Consider filtering out reversal setups between 22:00 - 06:00 UTC.</p>
              </div>
            </div>
          </CardContent>
        </Card>
      </div>
    </Layout>
  );
}
