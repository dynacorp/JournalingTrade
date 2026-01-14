import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { getTrades, getTrade, createTrade, updateTrade, type TradeInput } from "@/lib/api";
import type { Trade } from "@shared/schema";

export function useTrades(params?: {
  start_date?: string;
  end_date?: string;
  account_id?: string;
}) {
  return useQuery({
    queryKey: ["trades", params],
    queryFn: () => getTrades(params),
  });
}

export function useTrade(id: number | null) {
  return useQuery({
    queryKey: ["trades", id],
    queryFn: () => getTrade(id!),
    enabled: id !== null,
  });
}

export function useCreateTrade() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: (trade: TradeInput) => createTrade(trade),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["trades"] });
    },
  });
}

export function useUpdateTrade() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: ({ id, updates }: { id: number; updates: Partial<TradeInput> }) => 
      updateTrade(id, updates),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["trades"] });
    },
  });
}
