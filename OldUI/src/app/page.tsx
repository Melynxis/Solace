"use client";
import React, { useState, useEffect } from "react";

// API endpoint config
const REGISTRY_API = process.env.NEXT_PUBLIC_REGISTRY_API || "http://localhost:8081";

// Helper: Fetch spirits from Registry API
async function fetchSpirits() {
  const resp = await fetch(`${REGISTRY_API}/spirits`);
  if (!resp.ok) return [];
  return await resp.json();
}

const tabs = [
  { name: "Spirits" },
  { name: "Personality" },
  { name: "Registry" },
  { name: "Memory" },
  { name: "State" },
  { name: "RBAC" },
  { name: "Chat" },
];

export default function GhostpawDashboard() {
  const [activeTab, setActiveTab] = useState(0);
  const [spirits, setSpirits] = useState([]);
  const [selectedSpirit, setSelectedSpirit] = useState(null);
  const [matrixDraft, setMatrixDraft] = useState({});
  const [isFrozen, setIsFrozen] = useState(false);
  const [refresh, setRefresh] = useState(0);

  // Auto-refresh spirits list every 10s (or on refresh trigger)
  useEffect(() => {
    let cancelled = false;
    async function load() {
      const data = await fetchSpirits();
      if (!cancelled) setSpirits(data);
    }
    load();
    const timer = setInterval(load, 10000);
    return () => { cancelled = true; clearInterval(timer); };
  }, [refresh]);

  // When a spirit is selected, load its matrix into draft
  useEffect(() => {
    if (selectedSpirit) {
      setMatrixDraft(selectedSpirit.meta?.matrix || {});
      setIsFrozen(selectedSpirit.meta?.frozen || false);
    } else {
      setMatrixDraft({});
      setIsFrozen(false);
    }
  }, [selectedSpirit]);

  // Matrix editor handlers (stub for now)
  function handleMatrixChange(field, value) {
    setMatrixDraft({ ...matrixDraft, [field]: value });
  }

  // Freeze toggle (stub, would PATCH meta.frozen in real API)
  function handleFreeze() {
    setIsFrozen(f => !f);
    // TODO: PATCH /spirits/{id} meta: { frozen: !isFrozen }
  }

  // Save matrix (stub, would PATCH meta.matrix in real API)
  async function handleSave() {
    if (!selectedSpirit) return;
    // TODO: PATCH /spirits/{id} meta: { matrix: matrixDraft }
    alert("Save: Would persist matrix to backend (not implemented)");
  }

  // Test matrix (stub, would PATCH meta.matrix with temporary flag in real API)
  async function handleTest() {
    if (!selectedSpirit) return;
    // TODO: PATCH /spirits/{id} meta: { matrix: matrixDraft, temporary: true }
    alert("Test: Would apply temp matrix (not implemented)");
  }

  // Archive spirit (stub for now)
  async function handleArchive() {
    if (!selectedSpirit) return;
    // TODO: PUT /spirits/{id}/state new_state=archived
    alert("Archive: Would move spirit to cold storage (not implemented)");
  }

  // Backup spirit (stub for now)
  async function handleBackup() {
    if (!selectedSpirit) return;
    // TODO: GET /spirits/{id} and store JSON locally or trigger server backup
    alert("Backup: Would create backup JSON (not implemented)");
  }

  // Push to GitHub (disabled, Daisy required)
  function handlePushGithub() {
    alert("Push to GitHub: Requires Daisy backend (coming soon)");
  }

  // Migrate spirit (disabled, Eira/Serene required)
  function handleMigrate() {
    alert("Migrate: Hot migration to Eira/Serene coming soon");
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-[#23233a] to-[#18181f] text-gray-100">
      <div className="max-w-4xl mx-auto py-8 px-4">
        <h1 className="text-3xl font-extrabold text-violet-300 drop-shadow mb-8 text-center tracking-wider">
          Ghostpaw Dashboard
        </h1>
        <div className="flex space-x-2 mb-8">
          {tabs.map((tab, idx) => (
            <button
              key={tab.name}
              onClick={() => setActiveTab(idx)}
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
        <div className="bg-[#20202a] rounded-b-lg shadow p-6 min-h-[320px]">
          {activeTab === 0 && (
            <div>
              <h2 className="text-lg font-semibold text-violet-400 mb-2">Spirits</h2>
              <p className="text-gray-300 mb-4">
                List of all spirits. Select a spirit to view personality matrix in the Personality tab.
              </p>
              <div className="grid grid-cols-1 gap-2">
                {spirits.length === 0 ? (
                  <span className="text-gray-400 italic">No spirits present.</span>
                ) : (
                  spirits.map(spirit => (
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
          {activeTab === 1 && (
            <div className="flex h-[400px]">
              {/* Left: Spirit list */}
              <div className="w-1/3 border-r border-violet-900 pr-4 overflow-y-auto">
                <h3 className="text-violet-400 font-semibold mb-2">Spirits</h3>
                {spirits.length === 0 ? (
                  <span className="text-gray-400 italic">No spirits present.</span>
                ) : (
                  spirits.map(spirit => (
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
              {/* Right: Matrix editor */}
              <div className="flex-1 pl-6">
                {!selectedSpirit ? (
                  <div className="flex items-center justify-center h-full text-gray-400 italic">
                    Select a spirit to view/edit their personality matrix.
                  </div>
                ) : (
                  <div>
                    <div className="flex items-center justify-between mb-4">
                      <h3 className="text-2xl font-bold text-violet-200">{selectedSpirit.name}</h3>
                      <div>
                        <button
                          className={`mr-2 px-3 py-1 rounded text-white font-semibold ${
                            isFrozen ? "bg-gray-600" : "bg-teal-700 hover:bg-teal-800"
                          }`}
                          onClick={handleFreeze}
                        >
                          {isFrozen ? "Unfreeze" : "Freeze"}
                        </button>
                        <button
                          className="mr-2 px-3 py-1 rounded bg-violet-700 text-white font-semibold hover:bg-violet-800"
                          onClick={handleSave}
                          disabled={isFrozen}
                        >
                          Save
                        </button>
                        <button
                          className="mr-2 px-3 py-1 rounded bg-blue-700 text-white font-semibold hover:bg-blue-800"
                          onClick={handleTest}
                          disabled={isFrozen}
                        >
                          Test
                        </button>
                        <button
                          className="mr-2 px-3 py-1 rounded bg-gray-700 text-gray-300 font-semibold cursor-not-allowed"
                          title="Coming soon: hot-migrate to Eira/Serene"
                          disabled
                          onClick={handleMigrate}
                        >
                          Migrate
                        </button>
                        <button
                          className="mr-2 px-3 py-1 rounded bg-yellow-800 text-yellow-200 font-semibold"
                          title="Backup (stub, not implemented)"
                          onClick={handleBackup}
                        >
                          Backup
                        </button>
                        <button
                          className="mr-2 px-3 py-1 rounded bg-pink-800 text-pink-200 font-semibold"
                          title="Archive (stub, not implemented)"
                          onClick={handleArchive}
                        >
                          Archive
                        </button>
                        <button
                          className="px-3 py-1 rounded bg-gray-700 text-gray-300 font-semibold cursor-not-allowed"
                          title="Push to GitHub requires Daisy backend (coming soon)"
                          disabled
                          onClick={handlePushGithub}
                        >
                          Push to GitHub
                        </button>
                      </div>
                    </div>
                    <div className="mb-4">
                      <span className={`px-2 py-1 rounded text-sm ${
                        selectedSpirit.state === "ready"
                          ? "bg-green-700 text-green-200"
                          : selectedSpirit.state === "created"
                          ? "bg-blue-700 text-blue-200"
                          : selectedSpirit.state === "archived"
                          ? "bg-gray-700 text-gray-400"
                          : "bg-red-700 text-red-200"
                      }`}>{selectedSpirit.state}</span>
                      <span className="ml-3 text-gray-400">{selectedSpirit.role}</span>
                    </div>
                    {/* Personality Matrix editor (stub, show JSON for now) */}
                    <div className="border border-violet-800 rounded p-4 bg-[#22223c]">
                      <h4 className="text-lg font-semibold text-violet-400 mb-2">Personality Matrix</h4>
                      {isFrozen ? (
                        <div className="text-gray-400 italic mb-2">Matrix is frozen and cannot be edited.</div>
                      ) : (
                        <div className="mb-2 text-gray-300">
                          {/* Replace with actual matrix editor; for now, show JSON */}
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
          {/* ...other tabs unchanged... */}
        </div>
      </div>
    </div>
  );
}
