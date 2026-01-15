import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { apiRequest } from "@/lib/queryClient";
import type { MT5Account } from "@shared/schema";

interface CreateMT5AccountInput {
  name: string;
  account_id: string;
  broker: string;
  is_active?: boolean;
}

export function useMT5Accounts() {
  return useQuery({
    queryKey: ["mt5-accounts"],
    queryFn: async () => {
      const res = await apiRequest("GET", "/api/mt5-accounts");
      return await res.json() as MT5Account[];
    },
  });
}

export function useCreateMT5Account() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async (account: CreateMT5AccountInput) => {
      const res = await apiRequest("POST", "/api/mt5-accounts", account);
      return await res.json() as MT5Account;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["mt5-accounts"] });
    },
  });
}

export function useDeleteMT5Account() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async (id: number) => {
      await apiRequest("DELETE", `/api/mt5-accounts/${id}`);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["mt5-accounts"] });
    },
  });
}

export function useRegenerateMT5Key() {
  const queryClient = useQueryClient();
  
  return useMutation({
    mutationFn: async (id: number) => {
      const res = await apiRequest("POST", `/api/mt5-accounts/${id}/regenerate-key`);
      return await res.json() as MT5Account;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["mt5-accounts"] });
    },
  });
}
