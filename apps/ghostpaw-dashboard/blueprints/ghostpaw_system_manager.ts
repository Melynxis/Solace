// Ghostpaw System Manager (Blueprint)
// Interactive management for spirit services, health, and stack control

import { getServiceStatus, restartService, logAction } from './serviceControl';
import { getHealthAlerts, acknowledgeAlert } from './celesteHealth';
import { notifyAdmin, promptForAction } from './dashboard';

export async function handleCelesteAlert(spiritId: string, alert: HealthAlert) {
  // Display in dashboard
  notifyAdmin(`Health alert from Celeste: ${alert.description} (Spirit: ${spiritId})`);

  // Optionally auto-restart if idle and memory exceeded
  if (alert.type === 'memory' && alert.value > alert.threshold && alert.spiritIdle) {
    await restartService(spiritId);
    logAction(`Auto-restarted spirit ${spiritId} due to Celeste alert`);
    acknowledgeAlert(alert.id);
    notifyAdmin(`Spirit ${spiritId} restarted automatically.`);
  } else {
    // Prompt admin for decision if not clear-cut
    const action = await promptForAction(spiritId, alert);
    if (action === 'restart') {
      await restartService(spiritId);
      logAction(`Admin restarted spirit ${spiritId} after Celeste alert`);
    }
    acknowledgeAlert(alert.id);
  }
}

export async function manageService(spiritId: string, action: 'start'|'stop'|'restart') {
  await logAction(`Service ${action} requested for spirit ${spiritId}`);
  switch (action) {
    case 'start': /* ... */ break;
    case 'stop': /* ... */ break;
    case 'restart': await restartService(spiritId); break;
  }
  notifyAdmin(`Service ${action} completed for spirit ${spiritId}`);
}

// TODO: Expand with full dashboard integration, RBAC checks, audit trail, and API endpoints.