import { useCallback, useEffect, useState, type FormEvent } from 'react';
import MapView from './components/MapView';
import ReportList, { type Filters } from './components/ReportList';
import ReportDetail from './components/ReportDetail';
import AppLanding from './components/AppLanding';
import { AuthError, fetchReports, staffLogin, staffLogout, updateReportStatus } from './api';
import type { Report, StaffSession } from './types';
import './App.css';

const SESSION_STORAGE_KEY = 'aman_ai_staff_session';

function loadStoredSession(): StaffSession | null {
  try {
    const raw = localStorage.getItem(SESSION_STORAGE_KEY);
    return raw ? (JSON.parse(raw) as StaffSession) : null;
  } catch {
    return null;
  }
}

export default function App() {
  if (window.location.pathname === '/app' || window.location.pathname === '/app/') {
    return <AppLanding />;
  }

  const [session, setSession] = useState<StaffSession | null>(() => loadStoredSession());
  const [codeInput, setCodeInput] = useState('');
  const [authError, setAuthError] = useState('');
  const [loggingIn, setLoggingIn] = useState(false);

  const [reports, setReports] = useState<Report[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [filters, setFilters] = useState<Filters>({ status: 'all', department: 'all' });
  const [updating, setUpdating] = useState(false);
  const [loadError, setLoadError] = useState('');

  const logout = useCallback(() => {
    if (session) staffLogout(session.token);
    localStorage.removeItem(SESSION_STORAGE_KEY);
    setSession(null);
    setReports([]);
    setSelectedId(null);
  }, [session]);

  const load = useCallback(async () => {
    if (!session) return;
    try {
      // الإدارة العامة تقدر تفلتر بجهة معيّنة من القائمة؛ أي جهة أخرى مقصورة على بياناتها تلقائيًا بالخادم.
      const deptFilter = session.is_admin && filters.department !== 'all' ? filters.department : undefined;
      const data = await fetchReports(session.token, deptFilter);
      setReports(data);
      setLoadError('');
    } catch (e) {
      if (e instanceof AuthError) {
        logout();
        return;
      }
      setLoadError((e as Error).message);
    }
  }, [session, filters.department, logout]);

  useEffect(() => {
    if (!session) return;
    load();
    const id = setInterval(load, 8000);
    return () => clearInterval(id);
  }, [session, load]);

  const handleLogin = async (e: FormEvent) => {
    e.preventDefault();
    setLoggingIn(true);
    setAuthError('');
    try {
      const newSession = await staffLogin(codeInput.trim());
      localStorage.setItem(SESSION_STORAGE_KEY, JSON.stringify(newSession));
      setSession(newSession);
      setCodeInput('');
    } catch (e) {
      setAuthError((e as Error).message);
    } finally {
      setLoggingIn(false);
    }
  };

  const handleUpdateStatus = async (reportId: string, status: string) => {
    if (!session) return;
    setUpdating(true);
    try {
      await updateReportStatus(session.token, reportId, status);
      await load();
    } catch (e) {
      if (e instanceof AuthError) {
        logout();
        return;
      }
      window.alert((e as Error).message);
    } finally {
      setUpdating(false);
    }
  };

  if (!session) {
    return (
      <div className="login-gate">
        <form onSubmit={handleLogin} className="login-gate__card">
          <div className="login-gate__logo">A</div>
          <h1>داشبورد Aman AI</h1>
          <p>دخول موظفي الجهات المعنية — شرطة، إسعاف، دفاع مدني، أو مركز القيادة العام</p>
          <input
            type="password"
            placeholder="رمز دخول الجهة"
            value={codeInput}
            onChange={(e) => setCodeInput(e.target.value)}
            autoFocus
          />
          {authError && <p className="login-gate__error">{authError}</p>}
          <button type="submit" disabled={loggingIn}>
            {loggingIn ? '...جارٍ الدخول' : 'دخول'}
          </button>
          <p className="login-gate__hint">كل جهة إلها رمز دخول مستقل — راجع backend/.env.example للقيم التجريبية</p>
        </form>
      </div>
    );
  }

  const selectedReport = reports.find((r) => r.report_id === selectedId) ?? null;

  return (
    <div className="app-shell">
      <header className="app-header">
        <div className="app-header__brand">
          <div className="app-header__logo">A</div>
          <div>
            <h1>Aman AI</h1>
            <span>{session.label}</span>
          </div>
        </div>
        <div className="app-header__stats">
          <span>{reports.length} بلاغ مسجّل</span>
          {loadError && <span className="app-header__error">{loadError}</span>}
          <button className="app-header__logout" onClick={logout}>
            تسجيل الخروج
          </button>
        </div>
      </header>

      <div className="app-body">
        <ReportList
          reports={reports}
          selectedId={selectedId}
          onSelect={setSelectedId}
          filters={filters}
          onFiltersChange={setFilters}
          showDepartmentFilter={session.is_admin}
        />
        <div className="app-map">
          <MapView reports={reports} selectedId={selectedId} onSelect={setSelectedId} />
        </div>
        <ReportDetail report={selectedReport} onUpdateStatus={handleUpdateStatus} updating={updating} />
      </div>
    </div>
  );
}
