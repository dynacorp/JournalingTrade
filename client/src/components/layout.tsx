import { Link, useLocation } from "wouter";
import { LayoutDashboard, Calendar, LineChart, Settings, BookOpen, Menu } from "lucide-react";
import { cn } from "@/lib/utils";
import { Sheet, SheetContent, SheetTrigger } from "@/components/ui/sheet";
import { Button } from "@/components/ui/button";
import { useIsMobile } from "@/hooks/use-mobile";

const NAV_ITEMS = [
  { label: "Dashboard", icon: LayoutDashboard, href: "/" },
  { label: "Journal", icon: Calendar, href: "/journal" },
  { label: "Analysis", icon: LineChart, href: "/analysis" },
  { label: "Learning", icon: BookOpen, href: "/learning" },
  { label: "Settings", icon: Settings, href: "/settings" },
];

export function Layout({ children }: { children: React.ReactNode }) {
  const [location] = useLocation();
  const isMobile = useIsMobile();

  const SidebarContent = () => (
    <div className="flex flex-col h-full bg-sidebar border-r border-sidebar-border text-sidebar-foreground">
      <div className="p-6 border-b border-sidebar-border">
        <div className="flex items-center gap-2">
          <div className="w-8 h-8 rounded bg-primary flex items-center justify-center font-bold text-primary-foreground">TM</div>
          <span className="font-bold text-lg tracking-tight">TradeMind</span>
        </div>
      </div>
      <nav className="flex-1 p-4 space-y-2">
        {NAV_ITEMS.map((item) => {
          const isActive = location === item.href;
          return (
            <Link key={item.href} href={item.href}>
              <a className={cn(
                "flex items-center gap-3 px-4 py-2.5 rounded-md text-sm font-medium transition-colors",
                isActive 
                  ? "bg-sidebar-accent text-sidebar-accent-foreground" 
                  : "text-muted-foreground hover:bg-sidebar-accent/50 hover:text-sidebar-foreground"
              )}>
                <item.icon className="w-4 h-4" />
                {item.label}
              </a>
            </Link>
          );
        })}
      </nav>
      <div className="p-4 border-t border-sidebar-border">
        <div className="flex items-center gap-3 px-4 py-3 rounded-md bg-sidebar-accent/30 border border-sidebar-border/50">
          <div className="w-8 h-8 rounded-full bg-primary/20 flex items-center justify-center text-xs font-mono text-primary">JD</div>
          <div className="flex-1 overflow-hidden">
            <div className="text-sm font-medium truncate">John Doe</div>
            <div className="text-xs text-muted-foreground truncate">Pro Account</div>
          </div>
        </div>
      </div>
    </div>
  );

  return (
    <div className="min-h-screen bg-background text-foreground flex">
      {/* Desktop Sidebar */}
      <aside className="hidden md:block w-64 shrink-0 fixed inset-y-0 left-0 z-20">
        <SidebarContent />
      </aside>

      {/* Mobile Sidebar */}
      <div className="md:hidden fixed top-4 left-4 z-50">
        <Sheet>
          <SheetTrigger asChild>
            <Button variant="outline" size="icon" className="bg-background">
              <Menu className="w-4 h-4" />
            </Button>
          </SheetTrigger>
          <SheetContent side="left" className="p-0 w-64 border-r-sidebar-border bg-sidebar">
            <SidebarContent />
          </SheetContent>
        </Sheet>
      </div>

      {/* Main Content */}
      <main className="flex-1 md:ml-64 min-h-screen overflow-x-hidden">
        {children}
      </main>
    </div>
  );
}
