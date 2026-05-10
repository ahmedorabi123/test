import { http, HttpResponse } from "msw";
import { setupServer } from "msw/node";

const API = "*/api/v1";

export const handlers = [
  // Generic empty list endpoints used by various pages on first render.
  http.get(`${API}/orders`, () =>
    HttpResponse.json({
      data: [],
      meta: { total: 0, page: 1, per_page: 25, summary: { total_value: "0.00" } },
    })
  ),
  http.get(`${API}/refunds`, () =>
    HttpResponse.json({ data: [], meta: { total: 0, page: 1, per_page: 25 } })
  ),
  http.get(`${API}/shipments`, () =>
    HttpResponse.json({ data: [], meta: { total: 0, page: 1, per_page: 25 } })
  ),
  http.get(`${API}/users`, () =>
    HttpResponse.json({ data: [], meta: { total: 0, page: 1, per_page: 25 } })
  ),
  http.get(`${API}/roles`, () => HttpResponse.json({ data: [] })),
  http.get(`${API}/permissions`, () => HttpResponse.json({ data: [] })),
  http.get(`${API}/warehouses`, () => HttpResponse.json({ data: [] })),
  http.get(`${API}/variants`, () =>
    HttpResponse.json({ data: [], meta: { total: 0, page: 1, per_page: 25 } })
  ),
  http.get(`${API}/customers`, () =>
    HttpResponse.json({ data: [], meta: { total: 0, page: 1, per_page: 25 } })
  ),
];

export const server = setupServer(...handlers);
