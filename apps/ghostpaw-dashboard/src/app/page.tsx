"use client";
import React, { useState, useEffect } from "react";

// ---- CONFIG ----
const REGISTRY_API = process.env.NEXT_PUBLIC_REGISTRY_API || "http://localhost:8081";

// ---- LLM/Service Status Bar ----
const LLMs = [
  { name: "Finney", host: "192.168.1.20", port: 11434, type: "ollama", key: "finney" },
  { name: "Serene", host: "192.168.1.21", port: 11434, type: "ollama", key: "serene" },
  { name: "Veyra",  host: "192.168.1.100", port: 11434, type: "ollama", key: "veyra" },
  { name: "Gemini", host: "api.gemini.google.com", port: null, type: "gemini", key: "gemini" }, // Gemini API, stubbed
];

function getStatusColor(status: string) {
  if (status === "online") return "bg-green-600";
  if (status === "offcycle") return "bg-yellow-400";
  if (status === "offline") return "bg-red-600";
  return "bg-gray-700";
}

function getVeyraStatusByTime(now: Date) {
  // Veyra: green 00:00-06:00 daily, and Mon-Fri 08:00-17:00
  const h = now.getHours();
  const day = now.getDay(); // Sun=0, Mon=1, ..., Sat=6
  if (h >= 0 && h < 6) return "online";
  if (day >= 1 && day <= 5 && h >= 8 && h < 17) return "online";
  return "offcycle";
}

function LLMStatusBar({ statuses }: { statuses: Record<string, string> }) {
  return (
    <div className="flex flex-row gap-6 items-center justify-end mt-2">
      {LLMs.map(llm => {
        let tooltip = "";
        if (llm.key === "veyra") {
          tooltip = "Veyra is only available 00:00–06:00 AM daily and Mon–Fri 08:00–17:00. Otherwise, traffic is paused.";
        } else if (llm.key === "gemini") {
          tooltip = "Gemini 2.5 Flash API. May show yellow/red if throttled or offline.";
        } else {
          tooltip = `${llm.name} is available most hours unless offline.`;
        }
        return (
          <div className="flex flex-col items-center mx-2" key={llm.key}>
            <span
              className={`w-4 h-4 rounded-full ${getStatusColor(statuses[llm.key])} border-2 border-gray-300 mb-1`}
              title={tooltip + " (Status: " + (statuses[llm.key] || "unknown") + ")"}
            />
            <span className="text-xs font-semibold">{llm.name}</span>
            <span className="text-[10px] text-gray-400">{llm.host}{llm.port ? `:${llm.port}` : ""}</span>
          </div>
        );
      })}
    </div>
  );
}

// ---- LLM Status Polling Logic ----
async function checkOllamaStatus(host: string, port: number): Promise<"online"|"offline"> {
  try {
    // Try /api/tags endpoint for Ollama health (no auth required)
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 3500);
    const resp = await fetch(`http://${host}:${port}/api/tags`, { method: "GET", signal: controller.signal });
    clearTimeout(timeout);
    if (resp.ok) {
      return "online";
    }
    return "offline";
  } catch (err) {
    return "offline";
  }
}

async function checkGeminiStatus(): Promise<"online"|"offline"|"offcycle"> {
  // Stub: Always online for now. Could add direct API check if you want.
  return "online";
}

// ---- Spirits Tab API ----
async function fetchSpirits() {
  const resp = await fetch(`${REGISTRY_API}/spirits`);
  if (!resp.ok) return [];
  const json = await resp.json();
  if (Array.isArray(json)) return json;
  if (Array.isArray(json.data)) return json.data;
  return [];
}

// ---- Memory API (Weaviate) ----
async function fetchMemoryItems() {
  try {
    const resp = await fetch(`${REGISTRY_API}/memory`);
    if (!resp.ok) return [];
    const json = await resp.json();
    if (Array.isArray(json)) return json;
    if (Array.isArray(json.data)) return json.data;
    return [];
  } catch (err) {
    return [];
  }
}

// ---- Registry API ----
async function fetchRegistryServices() {
  const resp = await fetch(`${REGISTRY_API}/registry`);
  if (!resp.ok) return [];
  const json = await resp.json();
  if (Array.isArray(json)) return json;
  if (Array.isArray(json.data)) return json.data;
  return [];
}
async function createRegistryService(payload) {
  const resp = await fetch(`${REGISTRY_API}/registry`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  return await resp.json();
}
async function updateRegistryService(id, payload) {
  const resp = await fetch(`${REGISTRY_API}/registry/${id}`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  return await resp.json();
}
async function deleteRegistryService(id) {
  const resp = await fetch(`${REGISTRY_API}/registry/${id}`, {
    method: "DELETE",
  });
  return await resp.json();
}
const REGISTRY_TYPES = [
  "api", "tool", "exporter", "hook", "other"
];
const REGISTRY_STATUSES = [
  "active", "inactive", "error"
];

const tabs = [
  { name: "Spirits" },
  { name: "Personality" },
  { name: "Registry" },
  { name: "Memory" },
  { name: "State" },
  { name: "RBAC" },
  { name: "Chat" },
];

// ---- Main Dashboard ----
export default function GhostpawDashboard() {
  const [activeTab, setActiveTab] = useState(0);

  // LLM status
  const [llmStatuses, setLlmStatuses] = useState<Record<string, string>>({ finney: "unknown", serene: "unknown", veyra: "unknown", gemini: "unknown" });
  useEffect(() => {
    let cancelled = false;
    async function pollStatus() {
      const results: Record<string,string> = {};
      const now = new Date();
      for (const llm of LLMs) {
        if (llm.key === "veyra") {
          // Veyra: time-aware status
          const schedStatus = getVeyraStatusByTime(now);
          if (schedStatus === "online") {
            // Only poll if scheduled online
            const polledStatus = await checkOllamaStatus(llm.host, llm.port);
            results[llm.key] = polledStatus === "online" ? "online" : "offline";
          } else {
            results[llm.key] = "offcycle";
          }
        } else if (llm.type === "ollama") {
          results[llm.key] = await checkOllamaStatus(llm.host, llm.port);
        } else if (llm.type === "gemini") {
          results[llm.key] = await checkGeminiStatus();
        }
      }
      if (!cancelled) setLlmStatuses(results);
    }
    pollStatus();
    const timer = setInterval(pollStatus, 10000);
    return () => { cancelled = true; clearInterval(timer); };
  }, [activeTab]);

  // Spirits tab state
  const [spirits, setSpirits] = useState([]);
  const [selectedSpirit, setSelectedSpirit] = useState(null);
  const [matrixDraft, setMatrixDraft] = useState({});
  const [isFrozen, setIsFrozen] = useState(false);

  useEffect(() => {
    let cancelled = false;
    async function load() {
      const data = await fetchSpirits();
      if (!cancelled) setSpirits(data);
    }
    load();
    const timer = setInterval(load, 10000);
    return () => { cancelled = true; clearInterval(timer); };
  }, []);

  useEffect(() => {
    if (selectedSpirit) {
      setMatrixDraft(selectedSpirit.meta?.matrix || {});
      setIsFrozen(selectedSpirit.meta?.frozen || false);
    } else {
      setMatrixDraft({});
      setIsFrozen(false);
    }
  }, [selectedSpirit]);

  function handleMatrixChange(field, value) {
    setMatrixDraft({ ...matrixDraft, [field]: value });
  }

  function handleFreeze() {
    setIsFrozen(f => !f);
    // TODO: PATCH /spirits/{id} meta: { frozen: !isFrozen }
  }

  async function handleSave() {
    if (!selectedSpirit) return;
    // TODO: PATCH /spirits/{id} meta: { matrix: matrixDraft }
    alert("Save: Would persist matrix to backend (not implemented)");
  }

  async function handleTest() {
    if (!selectedSpirit) return;
    // TODO: PATCH /spirits/{id} meta: { matrix: matrixDraft, temporary: true }
    alert("Test: Would apply temp matrix (not implemented)");
  }

  async function handleArchive() {
    if (!selectedSpirit) return;
    // TODO: PUT /spirits/{id}/state new_state=archived
    alert("Archive: Would move spirit to cold storage (not implemented)");
  }

  async function handleBackup() {
    if (!selectedSpirit) return;
    // TODO: GET /spirits/{id} and store JSON locally or trigger server backup
    alert("Backup: Would create backup JSON (not implemented)");
  }

  function handlePushGithub() {
    alert("Push to GitHub: Requires Daisy backend (coming soon)");
  }

  function handlePullGithub() {
    alert("Pull from GitHub: Requires Daisy backend (coming soon)");
  }

  function handleMigrate() {
    alert("Migrate: Hot migration to Eira/Serene coming soon");
  }

  // ---- Registry tab state ----
  const [registryServices, setRegistryServices] = useState([]);
  const [selectedRegistry, setSelectedRegistry] = useState(null);
  const [showRegistryForm, setShowRegistryForm] = useState(false);
  const [formMode, setFormMode] = useState("add"); // "add" or "edit"
  const [formState, setFormState] = useState({
    name: "",
    type: "api",
    config: {},
    auth_mode: "none",
    status_: "active",
  });
  const [formError, setFormError] = useState(null);

  useEffect(() => {
    if (activeTab === 2) {
      fetchRegistryServices().then(setRegistryServices);
    }
  }, [activeTab]);

  function openAddRegistry() {
    setFormMode("add");
    setFormState({
      name: "",
      type: "api",
      config: {},
      auth_mode: "none",
      status_: "active",
    });
    setShowRegistryForm(true);
    setFormError(null);
  }

  function openEditRegistry(registry) {
    setFormMode("edit");
    setFormState({
      name: registry.name ?? "",
      type: registry.type ?? "api",
      config: registry.config ?? {},
      auth_mode: registry.auth_mode ?? "none",
      status_: registry.status ?? "active",
    });
    setSelectedRegistry(registry);
    setShowRegistryForm(true);
    setFormError(null);
  }

  async function submitRegistryForm(e) {
    e.preventDefault();
    setFormError(null);
    try {
      if (formMode === "add") {
        const resp = await createRegistryService(formState);
        if (resp.ok) {
          setShowRegistryForm(false);
          fetchRegistryServices().then(setRegistryServices);
        } else {
          setFormError(resp.error?.message ?? "Failed to create");
        }
      } else if (formMode === "edit" && selectedRegistry) {
        const resp = await updateRegistryService(selectedRegistry.id, formState);
        if (resp.ok) {
          setShowRegistryForm(false);
          setSelectedRegistry(null);
          fetchRegistryServices().then(setRegistryServices);
        } else {
          setFormError(resp.error?.message ?? "Failed to update");
        }
      }
    } catch (err) {
      setFormError("Network or server error");
    }
  }

  async function handleDeleteRegistry(registry) {
    if (!window.confirm(`Delete registry service "${registry.name}"? This cannot be undone.`)) return;
    const resp = await deleteRegistryService(registry.id);
    if (resp.ok) {
      setSelectedRegistry(null);
      fetchRegistryServices().then(setRegistryServices);
    } else {
      alert(resp.error?.message ?? "Failed to delete");
    }
  }

  // ---- Registry list row ----
  function RegistryRow({registry, onSelect, onEdit, onDelete}) {
    return (
      <tr className="hover:bg-violet-900/10 transition cursor-pointer">
        <td className="py-2 px-2 font-bold text-violet-300" onClick={() => onSelect(registry)}>{registry.name}</td>
        <td className="py-2 px-2">{registry.type}</td>
        <td className="py-2 px-2"><span className={`px-2 py-1 rounded text-xs ${
          registry.status === "active" ? "bg-green-600 text-green-100"
            : registry.status === "error" ? "bg-red-700 text-red-100"
            : "bg-gray-700 text-gray-200"
        }`}>{registry.status}</span></td>
        <td className="py-2 px-2">{registry.auth_mode}</td>
        <td className="py-2 px-2 flex gap-2">
          <button className="px-2 py-1 rounded bg-blue-800 text-white text-xs" onClick={e => {e.stopPropagation(); onEdit(registry);}}>Edit</button>
          <button className="px-2 py-1 rounded bg-red-700 text-white text-xs" onClick={e => {e.stopPropagation(); onDelete(registry);}}>Delete</button>
        </td>
      </tr>
    );
  }

  // ---- Registry form ----
  function RegistryForm() {
    return (
      <form className="space-y-4 bg-[#22223c] p-6 rounded shadow max-w-md mx-auto border border-violet-800" onSubmit={submitRegistryForm}>
        <h3 className="text-xl font-bold text-violet-300 mb-3">{formMode === "add" ? "Add Registry Service" : "Edit Registry Service"}</h3>
        <div>
          <label className="block text-violet-300 mb-1">Name</label>
          <input type="text" required className="w-full p-2 rounded bg-[#23233a] text-gray-100"
            value={formState.name}
            onChange={e => setFormState(s => ({...s, name: e.target.value}))}
          />
        </div>
        <div>
          <label className="block text-violet-300 mb-1">Type</label>
          <select className="w-full p-2 rounded bg-[#23233a] text-gray-100"
            value={formState.type}
            onChange={e => setFormState(s => ({...s, type: e.target.value}))}
          >
            {REGISTRY_TYPES.map(t => <option key={t} value={t}>{t}</option>)}
          </select>
        </div>
        <div>
          <label className="block text-violet-300 mb-1">Auth Mode</label>
          <input type="text" className="w-full p-2 rounded bg-[#23233a] text-gray-100"
            value={formState.auth_mode}
            onChange={e => setFormState(s => ({...s, auth_mode: e.target.value}))}
          />
        </div>
        <div>
          <label className="block text-violet-300 mb-1">Status</label>
          <select className="w-full p-2 rounded bg-[#23233a] text-gray-100"
            value={formState.status_}
            onChange={e => setFormState(s => ({...s, status_: e.target.value}))}
          >
            {REGISTRY_STATUSES.map(s => <option key={s} value={s}>{s}</option>)}
          </select>
        </div>
        <div>
          <label className="block text-violet-300 mb-1">Config (JSON)</label>
          <textarea className="w-full p-2 rounded bg-[#23233a] text-gray-100"
            value={JSON.stringify(formState.config ?? {}, null, 2)}
            onChange={e => {
              try {
                setFormState(s => ({...s, config: JSON.parse(e.target.value)}));
                setFormError(null);
              } catch {
                setFormError("Invalid JSON in config");
              }
            }}
            rows={4}
          />
        </div>
        {formError && <div className="text-red-400 text-sm">{formError}</div>}
        <div className="flex gap-4 pt-2">
          <button type="submit" className="px-4 py-2 rounded bg-violet-700 text-white font-semibold hover:bg-violet-800">
            {formMode === "add" ? "Add" : "Update"}
          </button>
          <button type="button" className="px-4 py-2 rounded bg-gray-700 text-white font-semibold" onClick={() => setShowRegistryForm(false)}>Cancel</button>
        </div>
      </form>
    );
  }

  // ---- Memory tab ----
  const [memoryItems, setMemoryItems] = useState([]);
  const [selectedMemory, setSelectedMemory] = useState(null);

  useEffect(() => {
    if (activeTab === 3) {
      fetchMemoryItems().then(setMemoryItems);
    }
  }, [activeTab]);

  function MemoryListTable() {
    return (
      <div className="overflow-x-auto mb-6">
        <table className="w-full bg-[#22223c] rounded shadow border border-violet-800">
          <thead>
            <tr className="bg-violet-900/20">
              <th className="py-2 px-2 text-left text-violet-300">Title</th>
              <th className="py-2 px-2 text-left text-violet-300">Source</th>
              <th className="py-2 px-2 text-left text-violet-300">Type</th>
              <th className="py-2 px-2 text-left text-violet-300">Timestamp</th>
              <th className="py-2 px-2 text-left text-violet-300">Actions</th>
            </tr>
          </thead>
          <tbody>
            {Array.isArray(memoryItems) && memoryItems.length === 0 ? (
              <tr>
                <td colSpan={5} className="text-center py-4 text-gray-400 italic">No memory items present.</td>
              </tr>
            ) : (
              memoryItems.map(mem => (
                <tr key={mem.id} className="hover:bg-violet-900/10 transition cursor-pointer">
                  <td className="py-2 px-2 font-bold text-violet-300"
                    onClick={() => setSelectedMemory(mem)}>{mem.title}</td>
                  <td className="py-2 px-2">{mem.source}</td>
                  <td className="py-2 px-2">{mem.type}</td>
                  <td className="py-2 px-2">{mem.timestamp}</td>
                  <td className="py-2 px-2 flex gap-2">
                    <button className="px-2 py-1 rounded bg-blue-800 text-white text-xs"
                      onClick={e => { e.stopPropagation(); setSelectedMemory(mem); }}>View</button>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    );
  }

  function MemoryDetailPanel() {
    return (
      <div className="bg-[#23233a] p-6 rounded shadow border border-violet-800 max-w-lg">
        <h3 className="text-xl font-bold text-violet-300 mb-2">{selectedMemory?.title}</h3>
        <div className="mb-2">
          <span className="font-semibold text-violet-400">Source:</span> {selectedMemory?.source}
        </div>
        <div className="mb-2">
          <span className="font-semibold text-violet-400">Type:</span> {selectedMemory?.type}
        </div>
        <div className="mb-2">
          <span className="font-semibold text-violet-400">Timestamp:</span> {selectedMemory?.timestamp}
        </div>
        <div className="mb-2">
          <span className="font-semibold text-violet-400">Raw Data:</span>
          <pre className="bg-[#18182f] rounded p-2 text-xs mt-1 overflow-x-auto">{JSON.stringify(selectedMemory, null, 2)}</pre>
        </div>
        <div className="mt-4 flex gap-2">
          <button className="px-3 py-1 rounded bg-gray-700 text-white text-xs"
            onClick={() => setSelectedMemory(null)}>Close</button>
        </div>
      </div>
    );
  }

  // ---- Main Render ----
  return (
    <div className="min-h-screen bg-gradient-to-br from-[#23233a] to-[#18181f] text-gray-100">
      <div className="max-w-[1500px] mx-auto py-10 px-10">
        <div className="flex items-center justify-between mb-3">
          <h1 className="text-3xl font-extrabold text-violet-300 drop-shadow tracking-wider">
            Ghostpaw Dashboard
          </h1>
          <LLMStatusBar statuses={llmStatuses} />
        </div>
        <div className="flex space-x-2 mb-8">
          {tabs.map((tab, idx) => (
            <button
              key={tab.name}
              onClick={() => {
                setActiveTab(idx);
                setSelectedSpirit(null);
                setSelectedRegistry(null);
                setShowRegistryForm(false);
                setSelectedMemory(null);
              }}
              className={`px-4 py-2 rounded-t-lg font-medium transition
                ${
                  activeTab === idx
                    ? "bg-violet-700 text-white shadow-lg"
                    : "bg-[#23233a] text-violet-300 hover:bg-violet-800 hover:text-white"
                }`}
            >
              {tab.name}
            </button>
          ))}
        </div>
        <div className="bg-[#20202a] rounded-b-lg shadow p-10 min-h-[400px]">
          {/* Spirits Tab */}
          {activeTab === 0 && (
            <div>
              <h2 className="text-lg font-semibold text-violet-400 mb-2">Spirits</h2>
              <p className="text-gray-300 mb-4">
                List of all spirits. Select a spirit to view personality matrix in the Personality tab.
              </p>
              <div className="grid grid-cols-1 gap-2">
                {Array.isArray(spirits) && spirits.length === 0 ? (
                  <span className="text-gray-400 italic">No spirits present.</span>
                ) : (
                  Array.isArray(spirits) && spirits.map(spirit => (
                    <div
                      key={spirit.id}
                      className="flex items-center justify-between p-3 rounded bg-[#23233a] border border-violet-800 hover:bg-violet-900 cursor-pointer"
                      onClick={() => { setSelectedSpirit(spirit); setActiveTab(1); }}
                    >
                      <div>
                        <span className="font-bold text-violet-300">{spirit.name}</span>
                        <span className="ml-2 text-gray-400">{spirit.role}</span>
                        <span className={`ml-2 px-2 py-1 rounded text-xs ${
                          spirit.state === "ready"
                            ? "bg-green-700 text-green-200"
                            : spirit.state === "created"
                            ? "bg-blue-700 text-blue-200"
                            : spirit.state === "archived"
                            ? "bg-gray-700 text-gray-400"
                            : "bg-red-700 text-red-200"
                        }`}>{spirit.state}</span>
                      </div>
                      <button
                        className="px-2 py-1 bg-violet-700 rounded text-white hover:bg-violet-800"
                        onClick={e => { e.stopPropagation(); setSelectedSpirit(spirit); setActiveTab(1); }}
                      >
                        Personality
                      </button>
                    </div>
                  ))
                )}
              </div>
            </div>
          )}
          {/* Personality Tab */}
          {activeTab === 1 && (
            <div className="flex h-[400px]">
              {/* Left: Spirit list */}
              <div className="w-1/3 border-r border-violet-900 pr-8 overflow-y-auto">
                <h3 className="text-violet-400 font-semibold mb-2">Spirits</h3>
                {Array.isArray(spirits) && spirits.length === 0 ? (
                  <span className="text-gray-400 italic">No spirits present.</span>
                ) : (
                  Array.isArray(spirits) && spirits.map(spirit => (
                    <div
                      key={spirit.id}
                      className={`p-2 rounded cursor-pointer mb-1 ${
                        selectedSpirit?.id === spirit.id
                          ? "bg-violet-800 text-white"
                          : "bg-[#23233a] text-violet-300 hover:bg-violet-700"
                      }`}
                      onClick={() => setSelectedSpirit(spirit)}
                    >
                      <span className="font-bold">{spirit.name}</span>
                      <span className="ml-2 text-gray-400">{spirit.role}</span>
                    </div>
                  ))
                )}
              </div>
              {/* Right: Matrix editor and actions */}
              <div className="flex-1 pl-10">
                {!selectedSpirit ? (
                  <div className="flex items-center justify-center h-full text-gray-400 italic">
                    Select a spirit to view/edit their personality matrix.
                  </div>
                ) : (
                  <div>
                    {/* Top row: name/role/state and actions */}
                    <div className="flex flex-row items-center justify-between mb-4 gap-4">
                      {/* Spirit name/role/state */}
                      <div className="flex flex-col gap-1">
                        <span className="text-2xl font-bold text-violet-200">{selectedSpirit.name}</span>
                        <div>
                          <span className={`px-2 py-1 rounded text-sm mr-2 ${
                            selectedSpirit.state === "ready"
                              ? "bg-green-700 text-green-200"
                              : selectedSpirit.state === "created"
                              ? "bg-blue-700 text-blue-200"
                              : selectedSpirit.state === "archived"
                              ? "bg-gray-700 text-gray-400"
                              : "bg-red-700 text-red-200"
                          }`}>{selectedSpirit.state}</span>
                          <span className="ml-1 text-gray-400">{selectedSpirit.role}</span>
                        </div>
                      </div>
                      {/* Actions: flex row, right-aligned */}
                      <div className="flex flex-row flex-wrap gap-2 justify-end">
                        <button className={`px-3 py-1 rounded text-white font-semibold ${isFrozen ? "bg-gray-600" : "bg-teal-700 hover:bg-teal-800"}`} onClick={handleFreeze}>
                          {isFrozen ? "Unfreeze" : "Freeze"}
                        </button>
                        <button className="px-3 py-1 rounded bg-violet-700 text-white font-semibold hover:bg-violet-800" onClick={handleSave} disabled={isFrozen}>
                          Save
                        </button>
                        <button className="px-3 py-1 rounded bg-blue-700 text-white font-semibold hover:bg-blue-800" onClick={handleTest} disabled={isFrozen}>
                          Test
                        </button>
                        <button className="px-3 py-1 rounded bg-gray-700 text-gray-300 font-semibold cursor-not-allowed" title="Coming soon: hot-migrate to Eira/Serene" disabled onClick={handleMigrate}>
                          Migrate
                        </button>
                        <button className="px-3 py-1 rounded bg-yellow-800 text-yellow-200 font-semibold" title="Backup (stub, not implemented)" onClick={handleBackup}>
                          Backup
                        </button>
                        <button className="px-3 py-1 rounded bg-pink-800 text-pink-200 font-semibold" title="Archive (stub, not implemented)" onClick={handleArchive}>
                          Archive
                        </button>
                      </div>
                    </div>
                    {/* Bottom row: Centered GitHub buttons */}
                    <div className="flex flex-row justify-center gap-8 mb-6">
                      <button
                        className="px-6 py-2 rounded bg-gray-700 text-gray-300 font-semibold w-[250px] text-lg shadow cursor-not-allowed"
                        style={{ marginTop: '0.5rem' }}
                        title="Push to GitHub requires Daisy backend (coming soon)"
                        disabled
                        onClick={handlePushGithub}
                      >
                        Push to GitHub
                      </button>
                      <button
                        className="px-6 py-2 rounded bg-gray-700 text-gray-300 font-semibold w-[250px] text-lg shadow cursor-not-allowed"
                        style={{ marginTop: '0.5rem' }}
                        title="Pull from GitHub requires Daisy backend (coming soon)"
                        disabled
                        onClick={handlePullGithub}
                      >
                        Pull from GitHub
                      </button>
                    </div>
                    {/* Personality Matrix editor */}
                    <div className="border border-violet-800 rounded p-6 bg-[#22223c]">
                      <h4 className="text-lg font-semibold text-violet-400 mb-2">Personality Matrix</h4>
                      {isFrozen ? (
                        <div className="text-gray-400 italic mb-2">Matrix is frozen and cannot be edited.</div>
                      ) : (
                        <div className="mb-2 text-gray-300">
                          <pre className="bg-[#1a1a2f] p-2 rounded text-xs overflow-x-auto">
                            {JSON.stringify(matrixDraft, null, 2)}
                          </pre>
                          <div className="mt-2">
                            {/* Example fields */}
                            <label className="block mb-1 text-violet-300">Empathy</label>
                            <input
                              type="number"
                              className="mb-2 p-1 rounded bg-[#23233a] text-gray-100 w-24"
                              value={matrixDraft.empathy ?? ""}
                              disabled={isFrozen}
                              onChange={e => handleMatrixChange("empathy", Number(e.target.value))}
                            />
                            <label className="block mb-1 text-violet-300">Curiosity</label>
                            <input
                              type="number"
                              className="mb-2 p-1 rounded bg-[#23233a] text-gray-100 w-24"
                              value={matrixDraft.curiosity ?? ""}
                              disabled={isFrozen}
                              onChange={e => handleMatrixChange("curiosity", Number(e.target.value))}
                            />
                            {/* Add more fields as needed */}
                          </div>
                        </div>
                      )}
                      <div className="mt-2 text-xs text-gray-400">
                        <span>
                          <strong>Note:</strong> Archive, Backup, Migrate, and GitHub sync are stubbed. Eira/Daisy integration will be added in future versions.
                        </span>
                      </div>
                    </div>
                  </div>
                )}
              </div>
            </div>
          )}
          {/* Registry Tab */}
          {activeTab === 2 && (
            <div>
              <div className="flex items-center justify-between mb-6">
                <h2 className="text-lg font-semibold text-violet-400">Registry Services</h2>
                <button className="px-4 py-2 rounded bg-violet-700 text-white font-semibold hover:bg-violet-800" onClick={openAddRegistry}>
                  Add New Service
                </button>
              </div>
              {/* Registry List Table */}
              <div className="overflow-x-auto mb-6">
                <table className="w-full bg-[#22223c] rounded shadow border border-violet-800">
                  <thead>
                    <tr className="bg-violet-900/20">
                      <th className="py-2 px-2 text-left text-violet-300">Name</th>
                      <th className="py-2 px-2 text-left text-violet-300">Type</th>
                      <th className="py-2 px-2 text-left text-violet-300">Status</th>
                      <th className="py-2 px-2 text-left text-violet-300">Auth</th>
                      <th className="py-2 px-2 text-left text-violet-300">Actions</th>
                    </tr>
                  </thead>
                  <tbody>
                    {Array.isArray(registryServices) && registryServices.length === 0 ? (
                      <tr>
                        <td colSpan={5} className="text-center py-4 text-gray-400 italic">No registry services present.</td>
                      </tr>
                    ) : (
                      registryServices.map(registry => (
                        <RegistryRow
                          key={registry.id}
                          registry={registry}
                          onSelect={setSelectedRegistry}
                          onEdit={openEditRegistry}
                          onDelete={handleDeleteRegistry}
                        />
                      ))
                    )}
                  </tbody>
                </table>
              </div>
              {/* Registry Details or Form */}
              {showRegistryForm ? (
                <RegistryForm />
              ) : selectedRegistry ? (
                <div className="bg-[#23233a] p-6 rounded shadow border border-violet-800 max-w-lg">
                  <h3 className="text-xl font-bold text-violet-300 mb-2">{selectedRegistry.name}</h3>
                  <div className="mb-2">
                    <span className="font-semibold text-violet-400">Type:</span> {selectedRegistry.type}
                  </div>
                  <div className="mb-2">
                    <span className="font-semibold text-violet-400">Status:</span> <span className={`px-2 py-1 rounded text-xs ${
                      selectedRegistry.status === "active" ? "bg-green-600 text-green-100"
                        : selectedRegistry.status === "error" ? "bg-red-700 text-red-100"
                        : "bg-gray-700 text-gray-200"
                    }`}>{selectedRegistry.status}</span>
                  </div>
                  <div className="mb-2">
                    <span className="font-semibold text-violet-400">Auth Mode:</span> {selectedRegistry.auth_mode}
                  </div>
                  <div className="mb-2">
                    <span className="font-semibold text-violet-400">Config:</span>
                    <pre className="bg-[#18182f] rounded p-2 text-xs mt-1 overflow-x-auto">{JSON.stringify(selectedRegistry.config, null, 2)}</pre>
                  </div>
                  <div className="mt-4 flex gap-2">
                    <button className="px-3 py-1 rounded bg-blue-800 text-white text-xs" onClick={() => openEditRegistry(selectedRegistry)}>Edit</button>
                    <button className="px-3 py-1 rounded bg-red-700 text-white text-xs" onClick={() => handleDeleteRegistry(selectedRegistry)}>Delete</button>
                    <button className="px-3 py-1 rounded bg-gray-700 text-white text-xs" onClick={() => setSelectedRegistry(null)}>Close</button>
                  </div>
                </div>
              ) : null}
            </div>
          )}
          {/* Memory Tab */}
          {activeTab === 3 && (
            <div>
              <div className="flex items-center justify-between mb-6">
                <h2 className="text-lg font-semibold text-violet-400">Semantic Memory Pipeline</h2>
                {/* Ingest button stub: connect to wiki_ingest.py later */}
                <button className="px-4 py-2 rounded bg-violet-700 text-white font-semibold hover:bg-violet-800"
                  onClick={() => {/* trigger ingest, stub */}}>Ingest Wiki Page</button>
              </div>
              <MemoryListTable />
              {selectedMemory ? <MemoryDetailPanel /> : null}
            </div>
          )}
          {/* Other tabs unchanged */}
          {activeTab !== 0 && activeTab !== 1 && activeTab !== 2 && activeTab !== 3 && (
            <div className="text-gray-400 italic">
              {activeTab === 4 && "State tab UI goes here."}
              {activeTab === 5 && "RBAC tab UI goes here."}
              {activeTab === 6 && "Chat tab UI goes here."}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
