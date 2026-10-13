import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from paattu.titles import clean_title, guess_language, playlist_title, song_key  # noqa: E402


class CleanTitleTest(unittest.TestCase):
    # Real uploads from Saregama, Think Music, Divo, Manorama, Sony and others.
    CASES = [
        ("Thalatherichavar - Video | Romancham | Sushin Shyam | Johnpaul George Productions | Jithu Madhavan | Saregama Malayalam",
         "Saregama Malayalam", "Thalatherichavar", "Romancham", "video"),
        ("Pakaliravukal - Video Song | Kurup | Dulquer Salmaan | Sobhita Dhulipala | Sushin Shyam | Anwar Ali | Saregama Malayalam",
         "Saregama Malayalam", "Pakaliravukal", "Kurup", "video"),
        ("Athmave Poo - Lyrical | Romancham | Sushin Shyam | Johnpaul George Productions | Jithu Madhavan | Saregama Malayalam",
         "", "Athmave Poo", "Romancham", "lyrical"),
        ("Kumki - Onnum Puriyala 8K 60 FPS Video Song | Vikram Prabhu, Lakshmi Menon | D. Imman",
         "", "Onnum Puriyala", "Kumki", "video"),
        ("Dorothy - Kanagamani Lyric Video | Karthik Subbaraj | Keerthy Suresh | Ilaiyaraaja",
         "", "Kanagamani", "Dorothy", "lyrical"),
        ("Wi Wi Wi Wi Wifi Video Song (4K) | S3 | Suriya | Anushka Shetty | Shruti Haasan | Harris Jayaraj",
         "", "Wi Wi Wi Wi Wifi", "S3", "video"),
        ("Naetru Aval Irundhal 8K 60FPS Video Song | Maryan | Dhanush, Parvathy | A.R. Rahman | Chinmayi",
         "", "Naetru Aval Irundhal", "Maryan", "video"),
        ("Mayilaadum Song | Paandi Nattu Thangam | Ilaiyaraaja | Karthik | Nirosha | Hi-Res Audio",
         "", "Mayilaadum", "Paandi Nattu Thangam", "audio"),
        ("Bhajare | Mr Brahmachari | Video | Mohanlal | K S Chithra | Gireesh Puthenchery | Mohan Sithara",
         "", "Bhajare", "Mr Brahmachari", "video"),
        ("Theliva Lyrical | #Love | Arjun Das, Aishwarya Lekshmi | Sean Roldan | Balaji Mohan | Netflix India",
         "", "Theliva", "Love", "lyrical"),
        ("Baasha Da - Video | Anbil Avan | Ashok Selvan | Preity Mukhundhan | Govind Vasantha | R.Kaarthikeyan",
         "", "Baasha Da", "Anbil Avan", "video"),
        ("Yeman Yaaru - Video Song | Indra | Vasanth Ravi | Mehreen Pirzada | ADK | Ajmal Tahseen",
         "", "Yeman Yaaru", "Indra", "video"),
        ("Exclusive – Unnande Kadhalena 8K Video Song | Vandha Mala | Sam D. Raj | Igore, Lakshmi",
         "", "Unnande Kadhalena", "Vandha Mala", "video"),
        ("Kanmani Anbodu Kadhalan (Lyric Video) | Guna | Kamal Haasan | Ilaiyaraaja",
         "", "Kanmani Anbodu Kadhalan", "Guna", "lyrical"),
        ("96 Songs| Kaathalae Kaathalae Song | Vijay Sethupathi, Trisha | Govind Vasantha | C. Prem Kumar",
         "Think Music India", "Kaathalae Kaathalae", "96", "video"),
        ("96 | Kaathalae Kaathalae Video Song | Vijay Sethupathi, Trisha | Govind Vasantha | C. Prem Kumar",
         "Think Music India", "Kaathalae Kaathalae", "96", "video"),
        ("Malare | Premam Song | Nivin Pauly", "", "Malare", "Premam", "video"),
        ("Malare - Premam Song | Nivin Pauly | Sai Pallavi",
         "", "Malare", "Premam", "video"),
        ("Hukum - Thalaivar Alappara (From \"Jailer\") | Anirudh Ravichander | Rajinikanth",
         "", "Hukum", "Jailer", "video"),
        ("Ullam Uruguthadi - Audio Jukebox | Ilaiyaraaja | Suresh, Viji | Erode N Murugesh",
         "", "Ullam Uruguthadi", "Ilaiyaraaja", "jukebox"),
        ("Vaathi Coming Video Song | Master | Thalapathy Vijay | Anirudh Ravichander | Lokesh Kanagaraj",
         "", "Vaathi Coming", "Master", "video"),
        ("The Third Murder | Official Movie Trailer | Saiju Kurup | Indrans",
         "", "The Third Murder", "Official Movie Trailer", "trailer"),
    ]

    def test_label_titles(self):
        for raw, channel, title, movie, kind in self.CASES:
            with self.subTest(raw=raw):
                got = clean_title(raw, channel)
                self.assertEqual(got["title"], title)
                self.assertEqual(got["movie"], movie)
                self.assertEqual(got["kind"], kind)

    def test_artist_first_on_the_artists_channel(self):
        got = clean_title("Sushin Shyam - Ray (Official Video)", "Sushin Shyam")
        self.assertEqual(got["title"], "Ray")

    def test_label_and_channel_are_not_credits(self):
        got = clean_title(self.CASES[0][0], "Saregama Malayalam")
        self.assertNotIn("Saregama Malayalam", got["credits"])
        self.assertEqual(got["credits"][0], "Sushin Shyam")

    def test_plain_title_passes_through(self):
        got = clean_title("Nenjukkul Peidhidum")
        self.assertEqual(got, {"title": "Nenjukkul Peidhidum", "movie": "", "credits": [], "kind": "video"})

    def test_song_key_matches_video_and_lyrical(self):
        video = clean_title("Athmave Poo - Video Song | Romancham | Sushin Shyam")
        lyrical = clean_title("Athmave Poo - Lyrical | Romancham | Sushin Shyam")
        self.assertEqual(song_key(video), song_key(lyrical))
        self.assertNotEqual(song_key(video), song_key(clean_title("Aadharanjali - Promo Song | Romancham")))


class PlaylistTitleTest(unittest.TestCase):
    def test_drops_label(self):
        self.assertEqual(playlist_title("Hits of Sushin Shyam | Saregama Malayalam"), "Hits of Sushin Shyam")
        self.assertEqual(playlist_title("Jukebox Mania | Non-Stop Malayalam Hits | Saregama Malayalam"), "Jukebox Mania")

    def test_drops_official_playlist(self):
        self.assertEqual(playlist_title("Karam - Official Playlist | Vineeth Sreenivasan | Shaan Rahman"), "Karam")


class LanguageTest(unittest.TestCase):
    def test_words_and_scripts(self):
        self.assertEqual(guess_language("Non-Stop Malayalam Hits"), "Malayalam")
        self.assertEqual(guess_language("Evergreen Tamil Melodies"), "Tamil")
        self.assertEqual(guess_language("തിരുവാതിരകളി വീഡിയോ"), "Malayalam")
        self.assertEqual(guess_language("பாட்டு"), "Tamil")
        self.assertEqual(guess_language("Hits of Sushin Shyam", default="Malayalam"), "Malayalam")
        self.assertEqual(guess_language("Lo-fi beats"), "")


if __name__ == "__main__":
    unittest.main()
