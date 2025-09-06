"use client";
import React, { useState, useEffect } from "react";

// ======= LLM/Service Status Bar =======
type ServiceStatus = "unknown" | "online" | "offline" | "partial";

const MODELS = [
  { name: "Finney", ip: "192.168.1.20", status: "unknown" as ServiceStatus },
  { name: "Serene", ip: "192.168.1.21", status: "unknown" as ServiceStatus },
  { name: "Veyra", ip: "192.168.1.100", status: "unknown" as ServiceStatus },
  { name: "Gemini", ip: "Google API", status: "unknown" as ServiceStatus },
];

function getStatusColor(status: ServiceStatus) {
  if (status === "online") return "bg-green-600";
  if (status === "partial") return "bg-yellow-400";
  if (status === "offline") return "bg-red-600";
  return "bg-gray-700";
}

function LLMStatusBar() {
  return (
    <div className="flex flex-row gap-6 items-center justify-end mt-2">
      {MODELS.map((model) => (
        <div className="flex flex-col items-center mx-2" key={model.name}>
          <span
            className={`w-4 h-4 rounded-full ${getStatusColor(model.status)} border-2 border-gray-300 mb-1`}
            title={model.status}
          />
          <span className="text-xs font-semibold">{model.name}</span>
          <span className="text-[10px] text-gray-400">{model.ip}</span>
        </div>
      ))}
    </div>
  );
}

// ======= Tabs =======
const tabs = [
  { name: "Spirits" },
  { name: "Personality" },
  { name: "Registry" },
  { name: "Memory" },
  { name: "State" },
  { name: "RBAC" },
  { name: "Chat" },
];

// ======= Spirits Tab - Fetch from API =======
function SpiritsListTable() {
  const [spirits, setSpirits] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // CHANGE THIS TO YOUR ACTUAL API URL IF NEEDED!
  const API_BASE = process.env.NEXT_PUBLIC_API_BASE || "http://127.0.0.1:8081";

  useEffect(() => {
    setLoading(true);
    setError(null);
    fetch(`${API_BASE}/spirits`)
      .then(r => r.json())
      .then(data => {
        if (data.ok && Array.isArray(data.data)) {
          setSpirits(data.data);
        } else {
          setError("Failed to load spirits.");
        }
        setLoading(false);
      })
      .catch(e => {
        setError("Error loading spirits: " + e.message);
        setLoading(false);
      });
  }, [API_BASE]);

  return (
    <div className="overflow-x-auto mb-6">
      <table className="w-full bg-[#22223c] rounded shadow border border-violet-800">
        <thead>
          <tr className="bg-violet-900/20">
            <th className="py-2 px-2 text-left text-violet-300">Name</th>
            <th className="py-2 px-2 text-left text-violet-300">Role</th>
            <th className="py-2 px-2 text-left text-violet-300">State</th>
            <th className="py-2 px-2 text-left text-violet-300">Created</th>
          </tr>
        </thead>
        <tbody>
          {loading ? (
            <tr>
              <td colSpan={4} className="text-center py-4 text-gray-400 italic">Loading...</td>
            </tr>
          ) : error ? (
            <tr>
              <td colSpan={4} className="text-center py-4 text-red-400">{error}</td>
            </tr>
          ) : spirits.length === 0 ? (
            <tr>
              <td colSpan={4} className="text-center py-4 text-gray-400 italic">No spirits present.</td>
            </tr>
          ) : (
            spirits.map(spirit => (
              <tr key={spirit.id} className="hover:bg-violet-900/10 transition cursor-pointer">
                <td className="py-2 px-2 font-bold text-violet-300">{spirit.name}</td>
                <td className="py-2 px-2">{spirit.role}</td>
                <td className="py-2 px-2">{spirit.state}</td>
                <td className="py-2 px-2">{spirit.created_at}</td>
              </tr>
            ))
          )}
        </tbody>
      </table>
    </div>
  );
}

// ======= Personality Tab (Stub) =======
const personalityStub = {
  traits: ["openness", "conscientiousness", "extraversion", "agreeableness", "neuroticism"],
  mood: {
    curiosity: 0.7,
    urgency: 0.3,
    warmth: 0.8,
    focus: 0.5,
  },
  style: ["empathetic", "formal", "playful"],
};

function PersonalityPanel() {
  return (
    <div className="bg-[#22223c] p-6 rounded shadow border border-violet-800 max-w-lg">
      <h3 className="text-xl font-bold text-violet-300 mb-2">Personality Summary</h3>
      <div className="mb-2">
        <span className="font-semibold text-violet-400">Core Traits:</span>
        <ul className="ml-4 list-disc">
          {personalityStub.traits.map(trait => (
            <li key={trait}>{trait}</li>
          ))}
        </ul>
      </div>
      <div className="mb-2">
        <span className="font-semibold text-violet-400">Mood State:</span>
        <ul className="ml-4 list-disc">
          {Object.entries(personalityStub.mood).map(([k, v]) => (
            <li key={k}>{k}: {v}</li>
          ))}
        </ul>
      </div>
      <div className="mb-2">
        <span className="font-semibold text-violet-400">Style Tokens:</span>
        <ul className="ml-4 list-disc">
          {personalityStub.style.map(token => (
            <li key={token}>{token}</li>
          ))}
        </ul>
      </div>
    </div>
  );
}

// ======= Registry Tab states (stub) =======
const registryServices = [
  { id: "1", name: "TestTool", type: "tool", status: "active", auth_mode: "none" },
  { id: "2", name: "TestTool2", type: "tool", status: "active", auth_mode: "none" },
];
const memoryItems = [
  { id: "m1", source: "wikipedia", type: "text", timestamp: "2025-09-06T02:00:00Z", title: "Semantic Memory Example" }
];

export default function GhostpawDashboard() {
  const [activeTab, setActiveTab] = useState(0);
  const [selectedRegistry, setSelectedRegistry] = useState<any>(null);
  const [showRegistryForm, setShowRegistryForm] = useState(false);
  const [selectedMemory, setSelectedMemory] = useState<any>(null);

  function RegistryListTable() {
    return (
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
            {registryServices.length === 0 ? (
              <tr>
                <td colSpan={5} className="text-center py-4 text-gray-400 italic">No registry services present.</td>
              </tr>
            ) : (
              registryServices.map(registry => (
                <tr key={registry.id} className="hover:bg-violet-900/10 transition cursor-pointer">
                  <td className="py-2 px-2 font-bold text-violet-300"
                    onClick={() => setSelectedRegistry(registry)}>{registry.name}</td>
                  <td className="py-2 px-2">{registry.type}</td>
                  <td className="py-2 px-2">
                    <span className="px-2 py-1 rounded text-xs bg-green-600 text-green-100">{registry.status}</span>
                  </td>
                  <td className="py-2 px-2">{registry.auth_mode}</td>
                  <td className="py-2 px-2 flex gap-2">
                    <button className="px-2 py-1 rounded bg-blue-800 text-white text-xs"
                      onClick={e => { e.stopPropagation(); setShowRegistryForm(true); setSelectedRegistry(registry); }}>Edit</button>
                    <button className="px-2 py-1 rounded bg-red-700 text-white text-xs"
                      onClick={e => { e.stopPropagation(); setSelectedRegistry(null); }}>Delete</button>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    );
  }

  function RegistryForm() {
    return (
      <form className="space-y-4 bg-[#22223c] p-6 rounded shadow max-w-md mx-auto border border-violet-800">
        <h3 className="text-xl font-bold text-violet-300 mb-3">Edit Registry Service</h3>
        <div>
          <label className="block text-violet-300 mb-1">Name</label>
          <input type="text" required className="w-full p-2 rounded bg-[#23233a] text-gray-100"
            value={selectedRegistry?.name || ""}
            disabled
          />
        </div>
        <div>
          <label className="block text-violet-300 mb-1">Type</label>
          <input type="text" className="w-full p-2 rounded bg-[#23233a] text-gray-100"
            value={selectedRegistry?.type || ""}
            disabled
          />
        </div>
        <div>
          <label className="block text-violet-300 mb-1">Auth Mode</label>
          <input type="text" className="w-full p-2 rounded bg-[#23233a] text-gray-100"
            value={selectedRegistry?.auth_mode || ""}
            disabled
          />
        </div>
        <div>
          <label className="block text-violet-300 mb-1">Status</label>
          <input type="text" className="w-full p-2 rounded bg-[#23233a] text-gray-100"
            value={selectedRegistry?.status || ""}
            disabled
          />
        </div>
        <div>
          <label className="block text-violet-300 mb-1">Config (JSON)</label>
          <textarea className="w-full p-2 rounded bg-[#23233a] text-gray-100"
            value={JSON.stringify(selectedRegistry?.config || { foo: "bar" }, null, 2)}
            disabled
            rows={4}
          />
        </div>
        <div className="flex gap-4 pt-2">
          <button type="button" className="px-4 py-2 rounded bg-gray-700 text-white font-semibold"
            onClick={() => setShowRegistryForm(false)}>Close</button>
        </div>
      </form>
    );
  }

  // ======= Memory Tab UI (stub) =======
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
            {memoryItems.length === 0 ? (
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

  // ======= Main Render =======
  return (
    <div className="min-h-screen bg-gradient-to-br from-[#23233a] to-[#18181f] text-gray-100">
      <div className="max-w-[1500px] mx-auto py-10 px-10">
        <div className="flex items-center justify-between mb-3">
          <h1 className="text-3xl font-extrabold text-violet-300 drop-shadow tracking-wider">
            Ghostpaw Dashboard
          </h1>
          <LLMStatusBar />
        </div>
        <div className="flex space-x-2 mb-8">
          {tabs.map((tab, idx) => (
            <button
              key={tab.name}
              onClick={() => {
                setActiveTab(idx);
                setSelectedRegistry(null);
                setSelectedMemory(null);
                setShowRegistryForm(false);
              }}
              className={`px-4 py-2 rounded-t-lg font-medium transition
                ${activeTab === idx ? "bg-violet-700 text-white shadow-lg" : "bg-[#23233a] text-violet-300 hover:bg-violet-800 hover:text-white"}`}
            >
              {tab.name}
            </button>
          ))}
        </div>
        <div className="bg-[#20202a] rounded-b-lg shadow p-10 min-h-[400px]">
          {/* Spirits Tab */}
          {activeTab === 0 && (
            <div>
              <h2 className="text-lg font-semibold text-violet-400 mb-4">Spirits</h2>
              <SpiritsListTable />
            </div>
          )}
          {/* Personality Tab */}
          {activeTab === 1 && (
            <div>
              <h2 className="text-lg font-semibold text-violet-400 mb-4">Personality</h2>
              <PersonalityPanel />
            </div>
          )}
          {/* Registry Tab */}
          {activeTab === 2 && (
            <div>
              <div className="flex items-center justify-between mb-6">
                <h2 className="text-lg font-semibold text-violet-400">Registry Services</h2>
                <button className="px-4 py-2 rounded bg-violet-700 text-white font-semibold hover:bg-violet-800"
                  onClick={() => setShowRegistryForm(true)}>
                  Add New Service
                </button>
              </div>
              <RegistryListTable />
              {showRegistryForm && selectedRegistry ? <RegistryForm /> : null}
              {!showRegistryForm && selectedRegistry ? (
                <div className="bg-[#23233a] p-6 rounded shadow border border-violet-800 max-w-lg">
                  <h3 className="text-xl font-bold text-violet-300 mb-2">{selectedRegistry.name}</h3>
                  <div className="mb-2">
                    <span className="font-semibold text-violet-400">Type:</span> {selectedRegistry.type}
                  </div>
                  <div className="mb-2">
                    <span className="font-semibold text-violet-400">Status:</span>
                    <span className="px-2 py-1 rounded text-xs bg-green-600 text-green-100">{selectedRegistry.status}</span>
                  </div>
                  <div className="mb-2">
                    <span className="font-semibold text-violet-400">Auth Mode:</span> {selectedRegistry.auth_mode}
                  </div>
                  <div className="mb-2">
                    <span className="font-semibold text-violet-400">Config:</span>
                    <pre className="bg-[#18182f] rounded p-2 text-xs mt-1 overflow-x-auto">{JSON.stringify(selectedRegistry.config || { foo: "bar" }, null, 2)}</pre>
                  </div>
                  <div className="mt-4 flex gap-2">
                    <button className="px-3 py-1 rounded bg-blue-800 text-white text-xs"
                      onClick={() => setShowRegistryForm(true)}>Edit</button>
                    <button className="px-3 py-1 rounded bg-red-700 text-white text-xs"
                      onClick={() => setSelectedRegistry(null)}>Delete</button>
                    <button className="px-3 py-1 rounded bg-gray-700 text-white text-xs"
                      onClick={() => setSelectedRegistry(null)}>Close</button>
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
                <button className="px-4 py-2 rounded bg-violet-700 text-white font-semibold hover:bg-violet-800"
                  onClick={() => {/* trigger ingest, stub */}}>Ingest Wiki Page</button>
              </div>
              <MemoryListTable />
              {selectedMemory ? <MemoryDetailPanel /> : null}
            </div>
          )}
          {/* Other Tabs */}
          {activeTab >= 4 && (
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
