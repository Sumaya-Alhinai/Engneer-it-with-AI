import { createContext, PropsWithChildren, useCallback, useContext, useEffect, useMemo, useState } from 'react';
import * as api from './api';
import { loadSession, saveSession } from './session-store';
import type { Report, Session } from './types';

type AppState = {
  ready: boolean;
  session: Session | null;
  reports: Report[];
  loadingReports: boolean;
  error: string | null;
  continueAsGuest(): Promise<void>;
  signIn(email: string, password: string): Promise<void>;
  signUp(name: string, email: string, password: string): Promise<void>;
  confirmEmail(email: string, code: string): Promise<void>;
  signOut(): Promise<void>;
  refreshReports(): Promise<void>;
};

const Context = createContext<AppState | null>(null);

export function AppProvider({ children }: PropsWithChildren) {
  const [ready, setReady] = useState(false);
  const [session, setSession] = useState<Session | null>(null);
  const [reports, setReports] = useState<Report[]>([]);
  const [loadingReports, setLoadingReports] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    loadSession().then(setSession).finally(() => setReady(true));
  }, []);

  const accept = useCallback(async (next: Session) => {
    await saveSession(next);
    setSession(next);
    setError(null);
  }, []);

  const continueAsGuest = useCallback(async () => accept(await api.createGuest()), [accept]);
  const signIn = useCallback(async (email: string, password: string) => accept(await api.login(email, password)), [accept]);
  const signUp = useCallback(async (name: string, email: string, password: string) => { await api.register(name, email, password); }, []);
  const confirmEmail = useCallback(async (email: string, code: string) => accept(await api.verify(email, code)), [accept]);
  const signOut = useCallback(async () => {
    if (session) await api.logout(session.token);
    await saveSession(null);
    setSession(null);
    setReports([]);
  }, [session]);
  const refreshReports = useCallback(async () => {
    if (!session) return;
    setLoadingReports(true);
    try {
      setReports(await api.listReports(session.token));
      setError(null);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'تعذر تحميل البلاغات');
    } finally {
      setLoadingReports(false);
    }
  }, [session]);

  useEffect(() => {
    if (session) refreshReports();
  }, [session, refreshReports]);

  const value = useMemo(() => ({ ready, session, reports, loadingReports, error, continueAsGuest, signIn, signUp, confirmEmail, signOut, refreshReports }),
    [ready, session, reports, loadingReports, error, continueAsGuest, signIn, signUp, confirmEmail, signOut, refreshReports]);
  return <Context.Provider value={value}>{children}</Context.Provider>;
}

export function useApp() {
  const value = useContext(Context);
  if (!value) throw new Error('useApp must be used inside AppProvider');
  return value;
}

