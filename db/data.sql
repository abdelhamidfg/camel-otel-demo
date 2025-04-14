CREATE TABLE public.flights (
    id integer NOT NULL,
    flight_number character varying(20) NOT NULL,
    source_city character varying(100) NOT NULL,
    destination_city character varying(100) NOT NULL,
    flight_date character varying(20) NOT NULL,
    departure_time character varying(10),
    arrival_time character varying(10)
);


ALTER TABLE public.flights OWNER TO admin;

--
-- Name: flights_id_seq; Type: SEQUENCE; Schema: public; Owner: admin
--

CREATE SEQUENCE public.flights_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE public.flights_id_seq OWNER TO admin;

--
-- Name: flights_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: admin
--

ALTER SEQUENCE public.flights_id_seq OWNED BY public.flights.id;

INSERT INTO public.flights VALUES (1, 'AA101', 'Dubai', 'Doha', '2025-11-01', '08:00', '11:00');
INSERT INTO public.flights VALUES (2, 'BA202', 'London', 'New York', '2023-11-02', '09:30', '13:00');
INSERT INTO public.flights VALUES (3, 'DL303', 'Cairo', 'Dubai', '2023-11-03', '17:00', '09:00');
INSERT INTO public.flights VALUES (4, 'UA404', 'Chicago', 'San Francisco', '2023-11-04', '10:15', '13:45');
INSERT INTO public.flights VALUES (5, 'AF505', 'Doha', 'Dubai', '2023-11-05', '12:00', '13:30');
INSERT INTO public.flights VALUES (6, 'LH606', 'Frankfurt', 'Rome', '2023-11-06', '07:45', '10:00');
INSERT INTO public.flights VALUES (7, 'SQ707', 'Singapore', 'Tokyo', '2023-11-07', '14:00', '18:00');
INSERT INTO public.flights VALUES (8, 'QF808', 'Sydney', 'Melbourne', '2023-11-08', '06:30', '07:45');
INSERT INTO public.flights VALUES (9, 'EK909', 'Dubai', 'Mumbai', '2023-11-09', '05:30', '07:00');
INSERT INTO public.flights VALUES (10, 'AC010', 'Toronto', 'Vancouver', '2023-11-10', '15:00', '17:30'); 