import { useState, useEffect } from "react";
import { Layout } from "@/components/layout";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Switch } from "@/components/ui/switch";
import { Separator } from "@/components/ui/separator";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle, AlertDialogTrigger } from "@/components/ui/alert-dialog";
import { Badge } from "@/components/ui/badge";
import { useToast } from "@/hooks/use-toast";
import { useMT5Accounts, useCreateMT5Account, useDeleteMT5Account, useRegenerateMT5Key } from "@/hooks/use-mt5-accounts";
import { User, Bell, Palette, Database, Plus, Copy, RefreshCw, Trash2, Key, Loader2, CheckCircle2, ExternalLink, Sparkles } from "lucide-react";
import { format } from "date-fns";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { apiRequest } from "@/lib/queryClient";

export default function Settings() {
  const { toast } = useToast();
  const queryClient = useQueryClient();
  const { data: mt5Accounts = [], isLoading } = useMT5Accounts();
  const createAccount = useCreateMT5Account();
  const deleteAccount = useDeleteMT5Account();
  const regenerateKey = useRegenerateMT5Key();

  const [isDialogOpen, setIsDialogOpen] = useState(false);
  const [newAccount, setNewAccount] = useState({ name: "", account_id: "", broker: "" });
  const [copiedKey, setCopiedKey] = useState<number | null>(null);

  const { data: aiSetting } = useQuery({
    queryKey: ["settings", "ai_analysis_enabled"],
    queryFn: async () => {
      const res = await apiRequest("GET", "/api/settings/ai_analysis_enabled");
      return res.json();
    },
  });

  const aiEnabled = aiSetting?.value !== "false";

  const updateAiSetting = useMutation({
    mutationFn: async (enabled: boolean) => {
      await apiRequest("PUT", "/api/settings/ai_analysis_enabled", { value: enabled ? "true" : "false" });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["settings", "ai_analysis_enabled"] });
      toast({ title: "Updated", description: "AI analysis setting saved" });
    },
  });

  const handleCreateAccount = async () => {
    if (!newAccount.name || !newAccount.account_id || !newAccount.broker) {
      toast({ title: "Error", description: "All fields are required", variant: "destructive" });
      return;
    }
    
    try {
      await createAccount.mutateAsync({
        ...newAccount,
        initial_balance: 0
      });
      toast({ title: "Success", description: "MT5 account connected successfully" });
      setNewAccount({ name: "", account_id: "", broker: "" });
      setIsDialogOpen(false);
    } catch (error: any) {
      toast({ title: "Error", description: error.message || "Failed to connect account", variant: "destructive" });
    }
  };

  const handleCopyKey = (id: number, key: string) => {
    navigator.clipboard.writeText(key);
    setCopiedKey(id);
    toast({ title: "Copied!", description: "Ingestion key copied to clipboard" });
    setTimeout(() => setCopiedKey(null), 2000);
  };

  const handleRegenerateKey = async (id: number) => {
    try {
      await regenerateKey.mutateAsync(id);
      toast({ title: "Success", description: "Ingestion key regenerated. Update your EA with the new key." });
    } catch (error) {
      toast({ title: "Error", description: "Failed to regenerate key", variant: "destructive" });
    }
  };

  const handleDeleteAccount = async (id: number) => {
    try {
      await deleteAccount.mutateAsync(id);
      toast({ title: "Deleted", description: "MT5 account disconnected" });
    } catch (error) {
      toast({ title: "Error", description: "Failed to delete account", variant: "destructive" });
    }
  };

  return (
    <Layout>
      <div className="p-8 space-y-8 max-w-[900px] mx-auto">
        <div className="flex flex-col gap-2">
          <h1 className="text-3xl font-bold tracking-tight">Settings</h1>
          <p className="text-muted-foreground">Manage your MT5 connections and application preferences.</p>
        </div>

        <div className="space-y-6">
          <Card>
            <CardHeader>
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <Database className="w-5 h-5 text-primary" />
                  <CardTitle>MT5 Connections</CardTitle>
                </div>
                <Dialog open={isDialogOpen} onOpenChange={setIsDialogOpen}>
                  <DialogTrigger asChild>
                    <Button size="sm" data-testid="button-add-mt5">
                      <Plus className="w-4 h-4 mr-2" />
                      Connect Account
                    </Button>
                  </DialogTrigger>
                  <DialogContent>
                    <DialogHeader>
                      <DialogTitle>Connect MT5 Account</DialogTitle>
                      <DialogDescription>
                        Add your MetaTrader 5 account to receive trades from your EA.
                      </DialogDescription>
                    </DialogHeader>
                    <div className="space-y-4 py-4">
                      <div className="space-y-2">
                        <Label htmlFor="name">Display Name</Label>
                        <Input 
                          id="name" 
                          placeholder="My Trading Account"
                          value={newAccount.name}
                          onChange={(e) => setNewAccount({ ...newAccount, name: e.target.value })}
                          data-testid="input-mt5-name"
                        />
                      </div>
                      <div className="space-y-2">
                        <Label htmlFor="account_id">Account ID</Label>
                        <Input 
                          id="account_id" 
                          placeholder="12345678"
                          value={newAccount.account_id}
                          onChange={(e) => setNewAccount({ ...newAccount, account_id: e.target.value })}
                          data-testid="input-mt5-account-id"
                        />
                        <p className="text-xs text-muted-foreground">Your MT5 account number</p>
                      </div>
                      <div className="space-y-2">
                        <Label htmlFor="broker">Broker</Label>
                        <Input
                          id="broker"
                          placeholder="Deriv, IC Markets, etc."
                          value={newAccount.broker}
                          onChange={(e) => setNewAccount({ ...newAccount, broker: e.target.value })}
                          data-testid="input-mt5-broker"
                        />
                      </div>
                    </div>
                    <DialogFooter>
                      <Button variant="outline" onClick={() => setIsDialogOpen(false)}>Cancel</Button>
                      <Button 
                        onClick={handleCreateAccount}
                        disabled={createAccount.isPending}
                        data-testid="button-create-mt5"
                      >
                        {createAccount.isPending && <Loader2 className="w-4 h-4 mr-2 animate-spin" />}
                        Connect
                      </Button>
                    </DialogFooter>
                  </DialogContent>
                </Dialog>
              </div>
              <CardDescription>
                Connect your MT5 accounts to automatically receive trades from your Expert Advisor.
              </CardDescription>
            </CardHeader>
            <CardContent>
              {isLoading ? (
                <div className="flex items-center justify-center py-8">
                  <Loader2 className="w-6 h-6 animate-spin text-muted-foreground" />
                </div>
              ) : mt5Accounts.length === 0 ? (
                <div className="text-center py-8 text-muted-foreground">
                  <Database className="w-12 h-12 mx-auto mb-4 opacity-50" />
                  <p>No MT5 accounts connected yet.</p>
                  <p className="text-sm">Click "Connect Account" to get started.</p>
                </div>
              ) : (
                <div className="space-y-4">
                  {mt5Accounts.map((account) => (
                    <div key={account.id} className="border border-border rounded-lg p-4 space-y-4">
                      <div className="flex items-start justify-between">
                        <div>
                          <div className="flex items-center gap-2">
                            <h4 className="font-semibold">{account.name}</h4>
                            <Badge variant={account.is_active ? "default" : "secondary"}>
                              {account.is_active ? "Active" : "Inactive"}
                            </Badge>
                          </div>
                          <p className="text-sm text-muted-foreground mt-1">
                            Account: <span className="font-mono">{account.account_id}</span> • {account.broker}
                          </p>
                          <p className="text-xs text-muted-foreground">
                            Connected {format(new Date(account.created_at), "MMM d, yyyy")}
                          </p>
                        </div>
                        <AlertDialog>
                          <AlertDialogTrigger asChild>
                            <Button variant="ghost" size="icon" className="text-destructive hover:text-destructive">
                              <Trash2 className="w-4 h-4" />
                            </Button>
                          </AlertDialogTrigger>
                          <AlertDialogContent>
                            <AlertDialogHeader>
                              <AlertDialogTitle>Delete MT5 Connection?</AlertDialogTitle>
                              <AlertDialogDescription>
                                This will remove the connection. Your EA will no longer be able to send trades.
                                Existing trades will not be deleted.
                              </AlertDialogDescription>
                            </AlertDialogHeader>
                            <AlertDialogFooter>
                              <AlertDialogCancel>Cancel</AlertDialogCancel>
                              <AlertDialogAction onClick={() => handleDeleteAccount(account.id)}>
                                Delete
                              </AlertDialogAction>
                            </AlertDialogFooter>
                          </AlertDialogContent>
                        </AlertDialog>
                      </div>
                      
                      <Separator />
                      
                      <div className="space-y-2">
                        <div className="flex items-center gap-2">
                          <Key className="w-4 h-4 text-muted-foreground" />
                          <Label className="text-sm">Ingestion API Key</Label>
                        </div>
                        <div className="flex gap-2">
                          <Input 
                            value={account.ingestion_key}
                            readOnly
                            className="font-mono text-xs flex-1"
                            data-testid={`input-key-${account.id}`}
                          />
                          <Button 
                            variant="outline" 
                            size="icon"
                            onClick={() => handleCopyKey(account.id, account.ingestion_key)}
                            data-testid={`button-copy-key-${account.id}`}
                          >
                            {copiedKey === account.id ? (
                              <CheckCircle2 className="w-4 h-4 text-profit" />
                            ) : (
                              <Copy className="w-4 h-4" />
                            )}
                          </Button>
                          <AlertDialog>
                            <AlertDialogTrigger asChild>
                              <Button variant="outline" size="icon">
                                <RefreshCw className="w-4 h-4" />
                              </Button>
                            </AlertDialogTrigger>
                            <AlertDialogContent>
                              <AlertDialogHeader>
                                <AlertDialogTitle>Regenerate API Key?</AlertDialogTitle>
                                <AlertDialogDescription>
                                  The current key will be invalidated. You'll need to update your EA with the new key.
                                </AlertDialogDescription>
                              </AlertDialogHeader>
                              <AlertDialogFooter>
                                <AlertDialogCancel>Cancel</AlertDialogCancel>
                                <AlertDialogAction onClick={() => handleRegenerateKey(account.id)}>
                                  Regenerate
                                </AlertDialogAction>
                              </AlertDialogFooter>
                            </AlertDialogContent>
                          </AlertDialog>
                        </div>
                        <p className="text-xs text-muted-foreground">
                          Use this key in your MT5 EA to authenticate trade submissions.
                        </p>
                      </div>

                      <div className="bg-muted/50 rounded-lg p-3 text-xs space-y-2">
                        <p className="font-medium">EA Configuration:</p>
                        <div className="font-mono bg-background p-2 rounded border border-border overflow-x-auto">
                          <p>Endpoint: POST /api/trades/ingest</p>
                          <p>Header: Authorization: Bearer {account.ingestion_key.slice(0, 8)}...</p>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <div className="flex items-center gap-2">
                <User className="w-5 h-5 text-primary" />
                <CardTitle>Profile</CardTitle>
              </div>
              <CardDescription>Your personal information.</CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="grid gap-4 md:grid-cols-2">
                <div className="space-y-2">
                  <Label htmlFor="name">Display Name</Label>
                  <Input id="name" defaultValue="Trader" data-testid="input-name" />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="timezone">Timezone</Label>
                  <Select defaultValue="utc">
                    <SelectTrigger data-testid="select-timezone">
                      <SelectValue placeholder="Select timezone" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="utc">UTC</SelectItem>
                      <SelectItem value="est">Eastern Time (EST)</SelectItem>
                      <SelectItem value="pst">Pacific Time (PST)</SelectItem>
                      <SelectItem value="gmt">GMT</SelectItem>
                      <SelectItem value="cet">Central European Time (CET)</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <div className="flex items-center gap-2">
                <Sparkles className="w-5 h-5 text-primary" />
                <CardTitle>AI Analysis</CardTitle>
              </div>
              <CardDescription>Configure OpenAI-powered trade analysis.</CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="flex items-center justify-between">
                <div className="space-y-0.5">
                  <Label>Enable AI Analysis</Label>
                  <p className="text-sm text-muted-foreground">Automatically analyze trades using OpenAI when they are ingested</p>
                </div>
                <Switch 
                  checked={aiEnabled} 
                  onCheckedChange={(checked) => updateAiSetting.mutate(checked)}
                  disabled={updateAiSetting.isPending}
                  data-testid="switch-ai-enabled" 
                />
              </div>
              <p className="text-xs text-muted-foreground">
                When disabled, trades will be saved without AI summaries. You can turn this off if you're experiencing API errors.
              </p>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <div className="flex items-center gap-2">
                <Bell className="w-5 h-5 text-primary" />
                <CardTitle>Notifications</CardTitle>
              </div>
              <CardDescription>Configure how you receive alerts.</CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="flex items-center justify-between">
                <div className="space-y-0.5">
                  <Label>Trade notifications</Label>
                  <p className="text-sm text-muted-foreground">Get notified when trades are closed</p>
                </div>
                <Switch defaultChecked data-testid="switch-trade-notif" />
              </div>
              <Separator />
              <div className="flex items-center justify-between">
                <div className="space-y-0.5">
                  <Label>AI analysis ready</Label>
                  <p className="text-sm text-muted-foreground">Notify when AI has analyzed a trade</p>
                </div>
                <Switch defaultChecked data-testid="switch-ai-notif" />
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <div className="flex items-center gap-2">
                <Palette className="w-5 h-5 text-primary" />
                <CardTitle>Appearance</CardTitle>
              </div>
              <CardDescription>Customize how TradeMind looks.</CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="grid gap-4 md:grid-cols-2">
                <div className="space-y-2">
                  <Label>Theme</Label>
                  <Select defaultValue="dark">
                    <SelectTrigger data-testid="select-theme">
                      <SelectValue placeholder="Select theme" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="dark">Dark</SelectItem>
                      <SelectItem value="light">Light</SelectItem>
                      <SelectItem value="system">System</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-2">
                  <Label>Currency Display</Label>
                  <Select defaultValue="usd">
                    <SelectTrigger data-testid="select-currency">
                      <SelectValue placeholder="Select currency" />
                    </SelectTrigger>
                    <SelectContent>
                      <SelectItem value="usd">USD ($)</SelectItem>
                      <SelectItem value="eur">EUR (€)</SelectItem>
                      <SelectItem value="gbp">GBP (£)</SelectItem>
                    </SelectContent>
                  </Select>
                </div>
              </div>
            </CardContent>
          </Card>

          <div className="flex justify-end gap-4">
            <Button variant="outline" data-testid="button-cancel">Cancel</Button>
            <Button data-testid="button-save">Save Changes</Button>
          </div>
        </div>
      </div>
    </Layout>
  );
}
